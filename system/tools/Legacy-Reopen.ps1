function Invoke-SystemV7LegacyStageReopen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][ValidateSet('K2B','K3')][string]$TargetStage,
        [Parameter(Mandatory)][ValidateSet('MISSING_EVIDENCE','ARCHITECTURE_CONFLICT','OVERLOADED_PACKET','UNSUPPORTED_BRIDGE','PROSE_CORRECTION','SOURCE_CHANGE','SCOPE_CHANGE','SCENE_WEAVE_CHANGE','QUESTION_REVEAL_CHANGE','SIGNIFICANT_K5_CORRECTION')][string]$ReasonCode,
        [Parameter(Mandatory)][string]$Scope,
        [ValidatePattern('^$|^ACT-\d{3}$')][string]$FromActId='',
        [switch]$DawidApproved,
        [Parameter(DontShow)][ValidateSet('','AFTER_FIRST_MOVE','AFTER_RECEIPT','AFTER_META_WRITE')][string]$InternalTestFaultPoint='',
        [Parameter(DontShow)][string]$InternalTestCreatedAtUtc=''
    )

    if ($InternalTestFaultPoint -or $InternalTestCreatedAtUtc) {
        $callerPath = if ($MyInvocation.ScriptName) { [IO.Path]::GetFullPath($MyInvocation.ScriptName) } else { '' }
        $allowedTestCaller = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Test-LegacyReopen.ps1'))
        if (-not $callerPath.Equals($allowedTestCaller,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'LEGACY_REOPEN_TEST_FAULT_UNAUTHORIZED'
        }
    }

    $TargetStage = $TargetStage.ToUpperInvariant()
    $ReasonCode = $ReasonCode.ToUpperInvariant()
    if ($Scope.Trim().Length -lt 8) { throw 'REOPEN_SCOPE_NOT_CONCRETE' }
    if ($FromActId) { throw 'LEGACY_REOPEN_FROM_ACT_UNSUPPORTED' }

    $project = [IO.Path]::GetFullPath($ProjectPath)
    $metaPath = Join-Path $project 'meta.md'
    $lock = Enter-SystemV7ProjectMetaLock -ProjectPath $project
    try {
        if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "META_MISSING: $metaPath" }
        $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
        $metaSha = (Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash
        $origin = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
        $workflow = Get-SystemV7NarrativeMetaField -Text $meta -Name 'WORKFLOW_REVISION'
        if ($workflow -cne '2026-08-30_K1_LITE_V2') { throw "LEGACY_REOPEN_WORKFLOW_UNSUPPORTED: $workflow" }

        $from = Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE'
        $route = "$from>$TargetStage"
        if ($route -notin @('K3>K2B','K4>K2B')) { throw "LEGACY_REOPEN_ROUTE_INVALID: $route" }
        $previousLastGate = Get-SystemV7NarrativeMetaField -Text $meta -Name 'LAST_GATE'
        $expectedInputGate = if ($from -ceq 'K3') { 'K2B_PASS' } else { 'K3_PASS' }
        if ($previousLastGate -cne $expectedInputGate) {
            throw 'LEGACY_REOPEN_INPUT_GATE_INVALID'
        }
        $allowedReasons = @('MISSING_EVIDENCE','ARCHITECTURE_CONFLICT','OVERLOADED_PACKET','UNSUPPORTED_BRIDGE','SOURCE_CHANGE','SCOPE_CHANGE')
        if ($ReasonCode -notin $allowedReasons) { throw "LEGACY_REOPEN_REASON_NOT_ALLOWED_FOR_ROUTE: $route/$ReasonCode" }
        $approvalMode = if ($ReasonCode -in @('SCOPE_CHANGE','SOURCE_CHANGE')) { 'DAWID_REQUIRED' } else { 'SYSTEM_ROUTE' }
        if ($approvalMode -ceq 'DAWID_REQUIRED' -and -not $DawidApproved) { throw 'DAWID_APPROVAL_REQUIRED' }

        $previousPath = Get-SystemV7NarrativeMetaField -Text $meta -Name 'LAST_STATE_RECEIPT_PATH'
        $previousSha = Get-SystemV7NarrativeMetaField -Text $meta -Name 'LAST_STATE_RECEIPT_SHA256'
        if (($previousPath -ceq 'BRAK') -xor ($previousSha -ceq 'BRAK')) { throw 'STATE_RECEIPT_HEAD_POINTER_INCOMPLETE' }
        if ($previousPath -cne 'BRAK') {
            $head = Get-StateReceiptHeadState -ProjectPath $project -MetaText $meta
            if (-not $head.Valid) { throw "CURRENT_STATE_RECEIPT_INVALID: $($head.Errors -join '; ')" }
        }

        $artifacts = [Collections.Generic.List[object]]::new()
        foreach ($relative in @('00-fundament-projektu.md','01-baza-dowodow.md','02-architektura-odcinka.md','03-draft.md','04-raport-qa.md','04B-fact-check.md','05-FINAL-SCRIPT.md')) {
            $path = Join-Path $project $relative
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Assert-SystemV7PathNoReparse -Path $path -ContainmentRoot $project | Out-Null
                $artifacts.Add([ordered]@{ relative=$relative; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash })
            }
        }
        if ($artifacts.Count -eq 0) { throw 'LEGACY_REOPEN_ARTIFACT_MANIFEST_EMPTY' }

        $invalidations = [Collections.Generic.List[object]]::new()
        foreach ($item in @('legacy K3 packets','legacy K3 draft','legacy K4 QA and Verify','legacy K5 final')) {
            $invalidations.Add([ordered]@{ artifact=$item; status='STALE'; scope=$Scope.Trim() })
        }

        $getMoveFingerprint = {
            param([string]$Path,[bool]$IsDirectory)
            if (-not $IsDirectory) {
                $item = Get-Item -LiteralPath $Path -Force
                return "FILE|$($item.Length)|$((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash)"
            }
            $root = [IO.Path]::GetFullPath($Path)
            $records = [Collections.Generic.List[object]]::new()
            foreach ($item in @(Get-ChildItem -LiteralPath $root -Recurse -Force | Sort-Object FullName)) {
                $relative = [IO.Path]::GetRelativePath($root,$item.FullName).Replace('\','/')
                if ($item.PSIsContainer) { $records.Add([ordered]@{kind='D';relative=$relative}) }
                else { $records.Add([ordered]@{kind='F';relative=$relative;bytes=[int64]$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash}) }
            }
            return Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value @($records))
        }

        $movePlan = [Collections.Generic.List[object]]::new()
        $moveSources = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $addMove = {
            param([string]$Source,[string]$ArchiveRelative)
            if (-not (Test-Path -LiteralPath $Source)) { return }
            $sourceFull = [IO.Path]::GetFullPath($Source)
            $sourceRelative = Get-SystemV7NarrativeRelativePath -Root $project -Path $sourceFull
            $isDirectory = Test-Path -LiteralPath $sourceFull -PathType Container
            if ($isDirectory) { Assert-SystemV7TreeNoReparse -RootPath $sourceFull -ContainmentRoot $project | Out-Null }
            else { Assert-SystemV7PathNoReparse -Path $sourceFull -ContainmentRoot $project | Out-Null }
            if ($moveSources.Add($sourceFull)) {
                $movePlan.Add([pscustomobject]@{
                    Source=$sourceFull
                    SourceRelative=$sourceRelative
                    ArchiveRelative=$ArchiveRelative
                    IsDirectory=$isDirectory
                    Fingerprint=(&$getMoveFingerprint $sourceFull $isDirectory)
                })
                $invalidations.Add([ordered]@{ artifact=$sourceRelative; status='ARCHIVE_ON_COMMIT'; scope=$Scope.Trim() })
            }
        }

        &$addMove (Join-Path $project '_work\k3-pakiety') 'k3-pakiety'
        foreach ($artifact in @('03-draft.md','04-raport-qa.md','04B-fact-check.md','05-FINAL-SCRIPT.md')) {
            &$addMove (Join-Path $project $artifact) "canonical/$artifact"
        }
        foreach ($workArtifact in @('_work\qa-baseline.md','_work\qa-baseline.receipt.json','_work\K4','_work\K5')) {
            &$addMove (Join-Path $project $workArtifact) ($workArtifact.Replace('\','/').Substring(6))
        }

        $put = { param($Text,$Name,$Value) Set-SystemV7NarrativeMetaField -Text $Text -Name $Name -Value $Value }
        $resultGate = 'K2_PASS'
        $updated = &$put $meta 'CURRENT_STAGE' 'K2B'
        $updated = &$put $updated 'STAGE_OWNER' 'ChatGPT'
        $updated = &$put $updated 'OWNER_OVERRIDE' 'BRAK'
        $updated = &$put $updated 'OWNER_OVERRIDE_RECEIPT_PATH' 'BRAK'
        $updated = &$put $updated 'OWNER_OVERRIDE_RECEIPT_SHA256' 'BRAK'
        $updated = &$put $updated 'LAST_STATE_RECEIPT_PATH' 'BRAK'
        $updated = &$put $updated 'LAST_STATE_RECEIPT_SHA256' 'BRAK'
        $updated = &$put $updated 'BLOCKED_FROM_STAGE' 'BRAK'
        $updated = &$put $updated 'BLOCKED_REASON' 'BRAK'
        $updated = &$put $updated 'LAST_GATE' $resultGate
        $updated = &$put $updated 'LAST_UPDATED' ([DateTime]::UtcNow.ToString('yyyy-MM-dd'))
        $updated = &$put $updated 'NEXT_ACTION' 'W K2B wykonaj zatwierdzony suplement K1, przebuduj architekturę i wygeneruj świeże paczki K3.'
        $handoffOwner = '(?m)^- Właściciel:\s*.*$'
        $handoffTask = '(?m)^- Zadanie:\s*.*$'
        if ([regex]::Matches($updated,$handoffOwner).Count -ne 1 -or [regex]::Matches($updated,$handoffTask).Count -ne 1) { throw 'HANDOFF_FIELDS_INVALID' }
        $updated = [regex]::Replace($updated,$handoffOwner,'- Właściciel: ChatGPT',1)
        $updated = [regex]::Replace($updated,$handoffTask,"- Zadanie: K2B — REOPEN $route — $ReasonCode — $($Scope.Trim())",1)

        $contextSha = Get-StateReceiptMetaContextSha256 -MetaText $updated
        $created = if ($InternalTestCreatedAtUtc) {
            $testCreated = [DateTimeOffset]::MinValue
            if (-not [DateTimeOffset]::TryParseExact($InternalTestCreatedAtUtc,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$testCreated)) {
                throw 'LEGACY_REOPEN_TEST_CREATED_AT_INVALID'
            }
            $testCreated.ToUniversalTime().ToString('o')
        } else { [DateTime]::UtcNow.ToString('o') }
        $record = New-SystemV7ReopenDecisionReceiptRecord `
            -ProjectOriginSha256 $origin.Sha256 -InputMetaSha256 $metaSha -ResultMetaContextSha256 $contextSha `
            -PreviousStateReceiptPath $previousPath -PreviousStateReceiptSha256 $previousSha `
            -FromStage $from -TargetStage 'K2B' -PreviousLastGate $previousLastGate -ResultLastGate $resultGate `
            -ReasonCode $ReasonCode -Scope $Scope.Trim() -ApprovalMode $approvalMode `
            -ArtifactHashesBefore @($artifacts) -InvalidationManifest @($invalidations) -CreatedAtUtc $created
        $intent = [string]$record.intent_sha256
        $systemStateRoot = Join-Path $project '_work\system'
        $systemStateRootExisted = Test-Path -LiteralPath $systemStateRoot -PathType Container
        $receiptDirectory = Join-Path $systemStateRoot 'state-decisions'
        $receiptDirectoryExisted = Test-Path -LiteralPath $receiptDirectory -PathType Container
        [IO.Directory]::CreateDirectory($receiptDirectory) | Out-Null
        $receiptPath = Join-Path $receiptDirectory "reopen-$intent.json"
        $receiptExistedBefore = Test-Path -LiteralPath $receiptPath -PathType Leaf
        $receiptCreated = $false
        $receiptSha = ''
        $receiptRelative = ''
        $archiveParent = Join-Path $project '_work\system\reopen-archives'
        $archiveParentExisted = Test-Path -LiteralPath $archiveParent -PathType Container
        $archiveRoot = Join-Path $archiveParent "reopen-$intent"
        $moved = [Collections.Generic.List[object]]::new()
        $archiveCreated = $false
        $metaWritten = $false
        $metaTransaction = $null
        $metaBeforeBytes = [IO.File]::ReadAllBytes($metaPath)
        try {
            if ((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -cne $metaSha) { throw 'REOPEN_COMPARE_AND_SWAP_CONFLICT' }
            if (Test-Path -LiteralPath $archiveRoot) { throw 'REOPEN_ARCHIVE_COLLISION' }
            [IO.Directory]::CreateDirectory($archiveRoot) | Out-Null
            $archiveCreated = $true
            foreach ($entry in @($movePlan)) {
                if (-not (Test-Path -LiteralPath $entry.Source)) { throw "REOPEN_SOURCE_CHANGED: $($entry.SourceRelative)" }
                $liveIsDirectory = Test-Path -LiteralPath $entry.Source -PathType Container
                if ($liveIsDirectory -ne [bool]$entry.IsDirectory -or (&$getMoveFingerprint $entry.Source $liveIsDirectory) -cne [string]$entry.Fingerprint) {
                    throw "REOPEN_SOURCE_CHANGED: $($entry.SourceRelative)"
                }
                $target = Join-Path $archiveRoot ([string]$entry.ArchiveRelative)
                [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
                if (Test-Path -LiteralPath $target) { throw "REOPEN_ARCHIVE_TARGET_EXISTS: $($entry.ArchiveRelative)" }
                if ($entry.IsDirectory) { [IO.Directory]::Move([string]$entry.Source,$target) }
                else { [IO.File]::Move([string]$entry.Source,$target) }
                $moved.Add([pscustomobject]@{Source=[string]$entry.Source;Target=$target;IsDirectory=[bool]$entry.IsDirectory})
                if ($InternalTestFaultPoint -ceq 'AFTER_FIRST_MOVE' -and $moved.Count -eq 1) {
                    throw 'LEGACY_REOPEN_TEST_FAULT_AFTER_FIRST_MOVE'
                }
            }
            Write-NewUtf8Json -Path $receiptPath -Value $record
            $receiptCreated = -not $receiptExistedBefore
            $receiptSha = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
            $receiptRelative = ([IO.Path]::GetRelativePath($project,$receiptPath)).Replace('\','/')
            if ($InternalTestFaultPoint -ceq 'AFTER_RECEIPT') { throw 'LEGACY_REOPEN_TEST_FAULT_AFTER_RECEIPT' }
            $updated = &$put $updated 'LAST_STATE_RECEIPT_PATH' $receiptRelative
            $updated = &$put $updated 'LAST_STATE_RECEIPT_SHA256' $receiptSha
            if ((Get-StateReceiptMetaContextSha256 -MetaText $updated) -cne $contextSha) { throw 'REOPEN_RESULT_META_CONTEXT_INTERNAL_MISMATCH' }
            $metaTransaction = Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text (ConvertTo-SystemV7LfText -Text $updated) -ExpectedCurrentSha256 $metaSha -HeldLockStream $lock -DeferFinalization
            $metaWritten = $true
            if ($InternalTestFaultPoint -ceq 'AFTER_META_WRITE') { throw 'LEGACY_REOPEN_TEST_FAULT_AFTER_META_WRITE' }
            $liveMeta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
            $headState = Get-StateReceiptHeadState -ProjectPath $project -MetaText $liveMeta
            if (-not $headState.Valid -or
                (Get-SystemV7NarrativeMetaField -Text $liveMeta -Name 'CURRENT_STAGE') -cne 'K2B' -or
                (Get-SystemV7NarrativeMetaField -Text $liveMeta -Name 'LAST_GATE') -cne $resultGate -or
                (Get-SystemV7NarrativeMetaField -Text $liveMeta -Name 'STAGE_OWNER') -cne 'ChatGPT') {
                throw "REOPEN_POSTVALIDATION_FAILED: $($headState.Errors -join '; ')"
            }
            foreach ($entry in @($moved)) {
                if ((Test-Path -LiteralPath $entry.Source) -or -not (Test-Path -LiteralPath $entry.Target)) { throw "REOPEN_ARCHIVE_POSTVALIDATION_FAILED: $($entry.Source)" }
            }
            Complete-SystemV7DeferredMetaTransaction -Transaction $metaTransaction
            $metaTransaction = $null
        } catch {
            $operationError = $_.Exception.Message
            $metaRollbackError = $null
            if ($null -ne $metaTransaction) {
                try {
                    Abort-SystemV7DeferredMetaTransaction -Transaction $metaTransaction -Reason $operationError
                    $metaTransaction = $null
                } catch {
                    $metaRollbackError = $_.Exception.Message
                }
            } elseif ($metaWritten) {
                # Normalnie nieosiągalne: po finalizacji nie ma już operacji,
                # które mogłyby rzucić wyjątek. Zachowujemy preimage jako
                # ostatnią ochronę kompatybilności starszych helperów CAS.
                [IO.File]::WriteAllBytes($metaPath,$metaBeforeBytes)
            }
            if ($receiptCreated -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { [IO.File]::Delete($receiptPath) }
            for ($index=$moved.Count-1; $index -ge 0; $index--) {
                $entry = $moved[$index]
                if (Test-Path -LiteralPath $entry.Target) {
                    [IO.Directory]::CreateDirectory((Split-Path -Parent $entry.Source)) | Out-Null
                    if ($entry.IsDirectory) { [IO.Directory]::Move($entry.Target,$entry.Source) }
                    else { [IO.File]::Move($entry.Target,$entry.Source) }
                }
            }
            if ($archiveCreated -and (Test-Path -LiteralPath $archiveRoot -PathType Container)) {
                $archiveRelative = Get-SystemV7NarrativeRelativePath -Root $project -Path $archiveRoot
                if ($archiveRelative -notmatch '^_work/system/reopen-archives/reopen-[A-F0-9]{64}$') { throw 'REOPEN_ARCHIVE_ROLLBACK_PATH_UNSAFE' }
                [IO.Directory]::Delete($archiveRoot,$true)
            }
            if (-not $archiveParentExisted -and (Test-Path -LiteralPath $archiveParent -PathType Container) -and @(Get-ChildItem -LiteralPath $archiveParent -Force).Count -eq 0) {
                [IO.Directory]::Delete($archiveParent,$false)
            }
            if (-not $receiptDirectoryExisted -and (Test-Path -LiteralPath $receiptDirectory -PathType Container) -and @(Get-ChildItem -LiteralPath $receiptDirectory -Force).Count -eq 0) {
                [IO.Directory]::Delete($receiptDirectory,$false)
            }
            if (-not $systemStateRootExisted -and (Test-Path -LiteralPath $systemStateRoot -PathType Container) -and @(Get-ChildItem -LiteralPath $systemStateRoot -Force).Count -eq 0) {
                $systemStateRelative = Get-SystemV7NarrativeRelativePath -Root $project -Path $systemStateRoot
                if ($systemStateRelative -cne '_work/system') { throw 'REOPEN_SYSTEM_ROOT_ROLLBACK_PATH_UNSAFE' }
                [IO.Directory]::Delete($systemStateRoot,$false)
            }
            if ($metaRollbackError) {
                throw "LEGACY_REOPEN_ROLLBACK_META_FAILED: $operationError; $metaRollbackError"
            }
            throw $operationError
        }

        [pscustomobject]@{
            Status='LEGACY_STAGE_REOPENED'
            FromStage=$from
            TargetStage='K2B'
            ReasonCode=$ReasonCode
            Scope=$Scope.Trim()
            ReceiptPath=$receiptPath
            ReceiptSha256=$receiptSha
            ArchivePath=$archiveRoot
            ArchivedItems=$moved.Count
            Invalidations=@($invalidations)
        }
    } finally {
        Exit-SystemV7ProjectMetaLock -LockStream $lock
    }
}
