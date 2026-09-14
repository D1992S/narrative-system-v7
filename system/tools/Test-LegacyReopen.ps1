[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$systemRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('system-v7-legacy-reopen-' + [guid]::NewGuid().ToString('N'))
$project = Join-Path $tempRoot 'fixture'

function Set-FixtureMetaField {
    param([string]$Path,[string]$Name,[string]$Value)
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $pattern = "(?m)^$([regex]::Escape($Name)):\s*.*$"
    if ([regex]::Matches($text,$pattern).Count -ne 1) { throw "FIXTURE_META_FIELD_INVALID: $Name" }
    $text = [regex]::Replace($text,$pattern,"${Name}: $Value",1)
    [IO.File]::WriteAllText($Path,$text,[Text.UTF8Encoding]::new($false))
}

function Get-FixtureTreeManifest {
    param([string]$Root)
    @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
            $relative = [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')
            if ($relative -ceq '.system-v7/meta-write.lock') { return }
            # Dziennik CAS jest celowo trwałym audytem próby. Jego stan jest
            # sprawdzany osobno; manifest porównuje całe aktywne drzewo projektu.
            if ($relative -match '^\.system-v7/meta-transactions(?:/|$)') { return }
            if ($_.PSIsContainer) { "D|$relative" }
            else { "F|$relative|$($_.Length)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }
        }
    )
}

function New-K4ReopenFixture {
    param([Parameter(Mandatory)][string]$Name)

    $fixtureProject = Join-Path $tempRoot $Name
    & (Join-Path $PSScriptRoot 'New-Project.ps1') -NarrativeV2Pilot:$false -ProjectName $Name -DestinationRoot $tempRoot -Channel 'inny' -Format 'STORYTELLING' -TargetMinutes 50 -RealWpm 130 | Out-Null
    Copy-Item -LiteralPath (Join-Path $systemRoot 'tools\compatibility\PROJECT-LEGACY-K1-LITE-V2\01-baza-dowodow.md') -Destination (Join-Path $fixtureProject '01-baza-dowodow.md')
    Copy-Item -LiteralPath (Join-Path $systemRoot 'tools\compatibility\PROJECT-LEGACY-K1-LITE-V2\02-architektura-odcinka.md') -Destination (Join-Path $fixtureProject '02-architektura-odcinka.md')

    $fixtureMetaPath = Join-Path $fixtureProject 'meta.md'
    Set-FixtureMetaField $fixtureMetaPath 'CURRENT_STAGE' 'K4'
    Set-FixtureMetaField $fixtureMetaPath 'STAGE_OWNER' 'ChatGPT'
    Set-FixtureMetaField $fixtureMetaPath 'LAST_GATE' 'K3_PASS'
    Set-FixtureMetaField $fixtureMetaPath 'K2B_DECISION' 'SUPLEMENT NIEWYMAGANY'
    $fixtureMeta = Get-Content -LiteralPath $fixtureMetaPath -Raw -Encoding UTF8
    $fixtureMeta = [regex]::Replace($fixtureMeta,'(?m)^- Właściciel:\s*.*$','- Właściciel: ChatGPT',1)
    $fixtureMeta = [regex]::Replace($fixtureMeta,'(?m)^- Zadanie:\s*.*$',"- Zadanie: K4 — $Name przed reopen.",1)
    [IO.File]::WriteAllText($fixtureMetaPath,$fixtureMeta,[Text.UTF8Encoding]::new($false))

    $fixtureSourcePath = Join-Path $fixtureProject 'sources\fixture.txt'
    [IO.File]::WriteAllText($fixtureSourcePath,"Źródło testowe K4 — nie zmieniać.`n",[Text.UTF8Encoding]::new($false))
    $fixturePacketDirectory = Join-Path $fixtureProject '_work\k3-pakiety'
    [IO.Directory]::CreateDirectory($fixturePacketDirectory) | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixturePacketDirectory 'AKT-1.md'),"packet K4 fixture`n",[Text.UTF8Encoding]::new($false))
    foreach ($artifact in @('03-draft.md','04-raport-qa.md','04B-fact-check.md')) {
        [IO.File]::WriteAllText((Join-Path $fixtureProject $artifact),"$artifact fixture`n",[Text.UTF8Encoding]::new($false))
    }
    [IO.Directory]::CreateDirectory((Join-Path $fixtureProject '_work\K4')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixtureProject '_work\K4\audit.md'),"audit fixture`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $fixtureProject '_work\qa-baseline.md'),"baseline fixture`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $fixtureProject '_work\qa-baseline.receipt.json'),"{}`n",[Text.UTF8Encoding]::new($false))

    [pscustomobject]@{
        Project = $fixtureProject
        MetaPath = $fixtureMetaPath
        PacketDirectory = $fixturePacketDirectory
    }
}

function Assert-FixtureTreeIdentity {
    param(
        [Parameter(Mandatory)][string[]]$Before,
        [Parameter(Mandatory)][string[]]$After,
        [Parameter(Mandatory)][string]$Label
    )
    if (($Before -join "`n") -cne ($After -join "`n")) {
        $delta = @(Compare-Object -ReferenceObject $Before -DifferenceObject $After | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
        throw "LEGACY_REOPEN_ROLLBACK_TREE_MISMATCH: $Label/$($delta -join '; ')"
    }
}

function Assert-K2BReopenState {
    param(
        [Parameter(Mandatory)][string]$FixtureProject,
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][string]$ExpectedFromStage,
        [Parameter(Mandatory)][string]$ExpectedPreviousGate,
        [Parameter(Mandatory)][string]$ExpectedReasonCode,
        [Parameter(Mandatory)][string]$ExpectedScope
    )

    $stateMetaPath = Join-Path $FixtureProject 'meta.md'
    $stateMeta = Get-Content -LiteralPath $stateMetaPath -Raw -Encoding UTF8
    $expectedFields = [ordered]@{
        WORKFLOW_REVISION = '2026-08-30_K1_LITE_V2'
        CURRENT_STAGE = 'K2B'
        STAGE_OWNER = 'ChatGPT'
        OWNER_OVERRIDE = 'BRAK'
        OWNER_OVERRIDE_RECEIPT_PATH = 'BRAK'
        OWNER_OVERRIDE_RECEIPT_SHA256 = 'BRAK'
        LAST_GATE = 'K2_PASS'
        BLOCKED_FROM_STAGE = 'BRAK'
        BLOCKED_REASON = 'BRAK'
    }
    foreach ($entry in $expectedFields.GetEnumerator()) {
        $actual = Get-SystemV7NarrativeMetaField -Text $stateMeta -Name $entry.Key
        if ($actual -cne [string]$entry.Value) { throw "LEGACY_REOPEN_STATE_FIELD_INVALID: $($entry.Key)/$actual" }
    }
    if ($stateMeta -notmatch '(?m)^- Właściciel:\s*ChatGPT\s*$' -or
        $stateMeta -notmatch "(?m)^- Zadanie:\s*K2B\s+—\s+REOPEN\s+$ExpectedFromStage>K2B\s+—\s+$ExpectedReasonCode") {
        throw 'LEGACY_REOPEN_STATE_HANDOFF_INVALID'
    }

    $receiptPathField = Get-SystemV7NarrativeMetaField -Text $stateMeta -Name 'LAST_STATE_RECEIPT_PATH'
    $receiptShaField = Get-SystemV7NarrativeMetaField -Text $stateMeta -Name 'LAST_STATE_RECEIPT_SHA256'
    $resultReceiptRelative = ([IO.Path]::GetRelativePath($FixtureProject,[string]$Result.ReceiptPath)).Replace('\','/')
    if ($receiptPathField -cne $resultReceiptRelative -or $receiptShaField -cne [string]$Result.ReceiptSha256 -or
        (Get-FileHash -LiteralPath $Result.ReceiptPath -Algorithm SHA256).Hash -cne [string]$Result.ReceiptSha256) {
        throw 'LEGACY_REOPEN_STATE_RECEIPT_POINTER_INVALID'
    }

    $headState = Get-StateReceiptHeadState -ProjectPath $FixtureProject -MetaText $stateMeta
    if (-not $headState.Valid -or $headState.Kind -cne 'REOPEN') {
        throw "LEGACY_REOPEN_STATE_RECEIPT_INVALID: $($headState.Errors -join '; ')"
    }
    $receiptExpectations = [ordered]@{
        from_stage = $ExpectedFromStage
        target_stage = 'K2B'
        previous_last_gate = $ExpectedPreviousGate
        result_last_gate = 'K2_PASS'
        reason_code = $ExpectedReasonCode
        scope = $ExpectedScope
        result_meta_context_sha256 = (Get-StateReceiptMetaContextSha256 -MetaText $stateMeta)
    }
    foreach ($entry in $receiptExpectations.GetEnumerator()) {
        $actual = [string](Get-ObjectPropertyValue -Object $headState.Data -Name $entry.Key)
        if ($actual -cne [string]$entry.Value) { throw "LEGACY_REOPEN_STATE_RECEIPT_FIELD_INVALID: $($entry.Key)/$actual" }
    }
    return $headState
}

try {
    [IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    . (Join-Path $PSScriptRoot 'Project-Origin.ps1')
    . (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
    . (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
    . (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
    . (Join-Path $PSScriptRoot 'Legacy-Reopen.ps1')
    & (Join-Path $PSScriptRoot 'New-Project.ps1') -NarrativeV2Pilot:$false -ProjectName 'fixture' -DestinationRoot $tempRoot -Channel 'inny' -Format 'STORYTELLING' -TargetMinutes 50 -RealWpm 130 | Out-Null
    Copy-Item -LiteralPath (Join-Path $systemRoot 'tools\compatibility\PROJECT-LEGACY-K1-LITE-V2\01-baza-dowodow.md') -Destination (Join-Path $project '01-baza-dowodow.md')
    Copy-Item -LiteralPath (Join-Path $systemRoot 'tools\compatibility\PROJECT-LEGACY-K1-LITE-V2\02-architektura-odcinka.md') -Destination (Join-Path $project '02-architektura-odcinka.md')
    $metaPath = Join-Path $project 'meta.md'
    Set-FixtureMetaField $metaPath 'CURRENT_STAGE' 'K3'
    Set-FixtureMetaField $metaPath 'STAGE_OWNER' 'Claude'
    Set-FixtureMetaField $metaPath 'LAST_GATE' 'K2B_PASS'
    Set-FixtureMetaField $metaPath 'K2B_DECISION' 'SUPLEMENT NIEWYMAGANY'
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    $meta = [regex]::Replace($meta,'(?m)^- Właściciel:\s*.*$','- Właściciel: Claude',1)
    $meta = [regex]::Replace($meta,'(?m)^- Zadanie:\s*.*$','- Zadanie: K3 — fixture przed reopen.',1)
    [IO.File]::WriteAllText($metaPath,$meta,[Text.UTF8Encoding]::new($false))

    $sourcePath = Join-Path $project 'sources\fixture.txt'
    [IO.File]::WriteAllText($sourcePath,"Źródło testowe — nie zmieniać.`n",[Text.UTF8Encoding]::new($false))
    $packetDirectory = Join-Path $project '_work\k3-pakiety'
    [IO.Directory]::CreateDirectory($packetDirectory) | Out-Null
    [IO.File]::WriteAllText((Join-Path $packetDirectory 'AKT-1.md'),"packet fixture`n",[Text.UTF8Encoding]::new($false))
    $draftPath = Join-Path $project '03-draft.md'
    [IO.File]::WriteAllText($draftPath,"draft fixture`n",[Text.UTF8Encoding]::new($false))

    $sourceHashBefore = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    $foundationHashBefore = (Get-FileHash -LiteralPath (Join-Path $project '00-fundament-projektu.md') -Algorithm SHA256).Hash
    $evidenceHashBefore = (Get-FileHash -LiteralPath (Join-Path $project '01-baza-dowodow.md') -Algorithm SHA256).Hash
    $architectureHashBefore = (Get-FileHash -LiteralPath (Join-Path $project '02-architektura-odcinka.md') -Algorithm SHA256).Hash

    $beforeRejected = @(Get-FixtureTreeManifest -Root $project)
    $approvalRejected = $false
    try {
        & (Join-Path $PSScriptRoot 'Reopen-Stage.ps1') -ProjectPath $project -TargetStage K2B -ReasonCode SCOPE_CHANGE -Scope 'Zmiana struktury fixture do ośmiu aktów.' | Out-Null
    } catch {
        $approvalRejected = $_.Exception.Message -match '^DAWID_APPROVAL_REQUIRED$'
    }
    if (-not $approvalRejected) { throw 'LEGACY_REOPEN_DID_NOT_REQUIRE_DAWID_APPROVAL' }
    $afterRejected = @(Get-FixtureTreeManifest -Root $project)
    if (($beforeRejected -join "`n") -cne ($afterRejected -join "`n")) { throw 'LEGACY_REOPEN_REJECTED_CALL_MUTATED_PROJECT' }

    $result = & (Join-Path $PSScriptRoot 'Reopen-Stage.ps1') -ProjectPath $project -TargetStage K2B -ReasonCode SCOPE_CHANGE -Scope 'Zmiana struktury fixture do ośmiu aktów.' -DawidApproved
    if ($result.Status -cne 'LEGACY_STAGE_REOPENED' -or $result.FromStage -cne 'K3' -or $result.TargetStage -cne 'K2B') { throw 'LEGACY_REOPEN_RESULT_INVALID' }

    $head = Assert-K2BReopenState -FixtureProject $project -Result $result -ExpectedFromStage 'K3' -ExpectedPreviousGate 'K2B_PASS' -ExpectedReasonCode 'SCOPE_CHANGE' -ExpectedScope 'Zmiana struktury fixture do ośmiu aktów.'
    if (Test-Path -LiteralPath $packetDirectory) { throw 'LEGACY_REOPEN_PACKET_DIRECTORY_NOT_ARCHIVED' }
    if (Test-Path -LiteralPath $draftPath) { throw 'LEGACY_REOPEN_DRAFT_NOT_ARCHIVED' }
    if (-not (Test-Path -LiteralPath (Join-Path $result.ArchivePath 'k3-pakiety\AKT-1.md') -PathType Leaf)) { throw 'LEGACY_REOPEN_ARCHIVED_PACKET_MISSING' }
    if (-not (Test-Path -LiteralPath (Join-Path $result.ArchivePath 'canonical\03-draft.md') -PathType Leaf)) { throw 'LEGACY_REOPEN_ARCHIVED_DRAFT_MISSING' }

    if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -cne $sourceHashBefore) { throw 'LEGACY_REOPEN_SOURCE_CHANGED' }
    if ((Get-FileHash -LiteralPath (Join-Path $project '00-fundament-projektu.md') -Algorithm SHA256).Hash -cne $foundationHashBefore) { throw 'LEGACY_REOPEN_FOUNDATION_CHANGED' }
    if ((Get-FileHash -LiteralPath (Join-Path $project '01-baza-dowodow.md') -Algorithm SHA256).Hash -cne $evidenceHashBefore) { throw 'LEGACY_REOPEN_EVIDENCE_CHANGED' }
    if ((Get-FileHash -LiteralPath (Join-Path $project '02-architektura-odcinka.md') -Algorithm SHA256).Hash -cne $architectureHashBefore) { throw 'LEGACY_REOPEN_ARCHITECTURE_CHANGED' }

    # Regresja K4>K2B: pełny powrót po wykryciu luki w architekturze musi
    # zarchiwizować wszystkie artefakty downstream, zachować K0/K1/K2 i zapisać
    # w receipcie rzeczywistą bramkę wejściową K3_PASS.
    $projectK4 = Join-Path $tempRoot 'fixture-k4'
    & (Join-Path $PSScriptRoot 'New-Project.ps1') -NarrativeV2Pilot:$false -ProjectName 'fixture-k4' -DestinationRoot $tempRoot -Channel 'inny' -Format 'STORYTELLING' -TargetMinutes 50 -RealWpm 130 | Out-Null
    Copy-Item -LiteralPath (Join-Path $systemRoot 'tools\compatibility\PROJECT-LEGACY-K1-LITE-V2\01-baza-dowodow.md') -Destination (Join-Path $projectK4 '01-baza-dowodow.md')
    Copy-Item -LiteralPath (Join-Path $systemRoot 'tools\compatibility\PROJECT-LEGACY-K1-LITE-V2\02-architektura-odcinka.md') -Destination (Join-Path $projectK4 '02-architektura-odcinka.md')
    $metaK4Path = Join-Path $projectK4 'meta.md'
    Set-FixtureMetaField $metaK4Path 'CURRENT_STAGE' 'K4'
    Set-FixtureMetaField $metaK4Path 'STAGE_OWNER' 'ChatGPT'
    Set-FixtureMetaField $metaK4Path 'LAST_GATE' 'K3_PASS'
    Set-FixtureMetaField $metaK4Path 'K2B_DECISION' 'SUPLEMENT NIEWYMAGANY'
    $metaK4 = Get-Content -LiteralPath $metaK4Path -Raw -Encoding UTF8
    $metaK4 = [regex]::Replace($metaK4,'(?m)^- Właściciel:\s*.*$','- Właściciel: ChatGPT',1)
    $metaK4 = [regex]::Replace($metaK4,'(?m)^- Zadanie:\s*.*$','- Zadanie: K4 — fixture przed reopen.',1)
    [IO.File]::WriteAllText($metaK4Path,$metaK4,[Text.UTF8Encoding]::new($false))

    $sourceK4Path = Join-Path $projectK4 'sources\fixture.txt'
    [IO.File]::WriteAllText($sourceK4Path,"Źródło testowe K4 — nie zmieniać.`n",[Text.UTF8Encoding]::new($false))
    $packetK4Directory = Join-Path $projectK4 '_work\k3-pakiety'
    [IO.Directory]::CreateDirectory($packetK4Directory) | Out-Null
    [IO.File]::WriteAllText((Join-Path $packetK4Directory 'AKT-1.md'),"packet K4 fixture`n",[Text.UTF8Encoding]::new($false))
    foreach ($artifact in @('03-draft.md','04-raport-qa.md','04B-fact-check.md')) {
        [IO.File]::WriteAllText((Join-Path $projectK4 $artifact),"$artifact fixture`n",[Text.UTF8Encoding]::new($false))
    }
    [IO.Directory]::CreateDirectory((Join-Path $projectK4 '_work\K4')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $projectK4 '_work\K4\audit.md'),"audit fixture`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $projectK4 '_work\qa-baseline.md'),"baseline fixture`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $projectK4 '_work\qa-baseline.receipt.json'),"{}`n",[Text.UTF8Encoding]::new($false))

    $sourceK4HashBefore = (Get-FileHash -LiteralPath $sourceK4Path -Algorithm SHA256).Hash
    $foundationK4HashBefore = (Get-FileHash -LiteralPath (Join-Path $projectK4 '00-fundament-projektu.md') -Algorithm SHA256).Hash
    $evidenceK4HashBefore = (Get-FileHash -LiteralPath (Join-Path $projectK4 '01-baza-dowodow.md') -Algorithm SHA256).Hash
    $architectureK4HashBefore = (Get-FileHash -LiteralPath (Join-Path $projectK4 '02-architektura-odcinka.md') -Algorithm SHA256).Hash

    $beforeK4Rejected = @(Get-FixtureTreeManifest -Root $projectK4)
    $reasonRejected = $false
    try {
        & (Join-Path $PSScriptRoot 'Reopen-Stage.ps1') -ProjectPath $projectK4 -TargetStage K2B -ReasonCode PROSE_CORRECTION -Scope 'Niedozwolony powód dla pełnego powrotu K4.' | Out-Null
    } catch {
        $reasonRejected = $_.Exception.Message -match '^LEGACY_REOPEN_REASON_NOT_ALLOWED_FOR_ROUTE:'
    }
    if (-not $reasonRejected) { throw 'LEGACY_K4_REOPEN_INVALID_REASON_NOT_REJECTED' }
    $afterK4Rejected = @(Get-FixtureTreeManifest -Root $projectK4)
    if (($beforeK4Rejected -join "`n") -cne ($afterK4Rejected -join "`n")) { throw 'LEGACY_K4_REOPEN_REJECTED_CALL_MUTATED_PROJECT' }

    $scopeK4 = 'Akt 6: brak kart dla wymaganego mostu nazw i transferów programu.'
    $resultK4 = & (Join-Path $PSScriptRoot 'Reopen-Stage.ps1') -ProjectPath $projectK4 -TargetStage K2B -ReasonCode ARCHITECTURE_CONFLICT -Scope $scopeK4
    if ($resultK4.Status -cne 'LEGACY_STAGE_REOPENED' -or $resultK4.FromStage -cne 'K4' -or $resultK4.TargetStage -cne 'K2B') { throw 'LEGACY_K4_REOPEN_RESULT_INVALID' }

    $headK4 = Assert-K2BReopenState -FixtureProject $projectK4 -Result $resultK4 -ExpectedFromStage 'K4' -ExpectedPreviousGate 'K3_PASS' -ExpectedReasonCode 'ARCHITECTURE_CONFLICT' -ExpectedScope $scopeK4
    foreach ($removed in @($packetK4Directory,(Join-Path $projectK4 '03-draft.md'),(Join-Path $projectK4 '04-raport-qa.md'),(Join-Path $projectK4 '04B-fact-check.md'),(Join-Path $projectK4 '_work\qa-baseline.md'),(Join-Path $projectK4 '_work\qa-baseline.receipt.json'),(Join-Path $projectK4 '_work\K4'))) {
        if (Test-Path -LiteralPath $removed) { throw "LEGACY_K4_REOPEN_ARTIFACT_NOT_ARCHIVED: $removed" }
    }
    foreach ($archived in @('k3-pakiety\AKT-1.md','canonical\03-draft.md','canonical\04-raport-qa.md','canonical\04B-fact-check.md','qa-baseline.md','qa-baseline.receipt.json','K4\audit.md')) {
        if (-not (Test-Path -LiteralPath (Join-Path $resultK4.ArchivePath $archived) -PathType Leaf)) { throw "LEGACY_K4_REOPEN_ARCHIVE_MISSING: $archived" }
    }
    if ((Get-FileHash -LiteralPath $sourceK4Path -Algorithm SHA256).Hash -cne $sourceK4HashBefore) { throw 'LEGACY_K4_REOPEN_SOURCE_CHANGED' }
    if ((Get-FileHash -LiteralPath (Join-Path $projectK4 '00-fundament-projektu.md') -Algorithm SHA256).Hash -cne $foundationK4HashBefore) { throw 'LEGACY_K4_REOPEN_FOUNDATION_CHANGED' }
    if ((Get-FileHash -LiteralPath (Join-Path $projectK4 '01-baza-dowodow.md') -Algorithm SHA256).Hash -cne $evidenceK4HashBefore) { throw 'LEGACY_K4_REOPEN_EVIDENCE_CHANGED' }
    if ((Get-FileHash -LiteralPath (Join-Path $projectK4 '02-architektura-odcinka.md') -Algorithm SHA256).Hash -cne $architectureK4HashBefore) { throw 'LEGACY_K4_REOPEN_ARCHITECTURE_CHANGED' }

    # Awaria po każdym punkcie mutacji musi cofnąć cały projekt bajt w bajt
    # (z wyjątkiem trwałego pliku blokady, który manifest celowo pomija).
    foreach ($faultPoint in @('AFTER_FIRST_MOVE','AFTER_RECEIPT','AFTER_META_WRITE')) {
        $faultFixture = New-K4ReopenFixture -Name ("fixture-k4-fault-" + $faultPoint.ToLowerInvariant().Replace('_','-'))
        $beforeFault = @(Get-FixtureTreeManifest -Root $faultFixture.Project)
        $expectedFault = "LEGACY_REOPEN_TEST_FAULT_$faultPoint"
        $faultObserved = $false
        try {
            Invoke-SystemV7LegacyStageReopen -ProjectPath $faultFixture.Project -TargetStage K2B -ReasonCode ARCHITECTURE_CONFLICT -Scope 'Akt 6: test pełnego rollbacku K4 do K2B.' -InternalTestFaultPoint $faultPoint | Out-Null
        } catch {
            if ($_.Exception.Message -cne $expectedFault) { throw }
            $faultObserved = $true
        }
        if (-not $faultObserved) { throw "LEGACY_REOPEN_FAULT_NOT_OBSERVED: $faultPoint" }
        $afterFault = @(Get-FixtureTreeManifest -Root $faultFixture.Project)
        Assert-FixtureTreeIdentity -Before $beforeFault -After $afterFault -Label $faultPoint
        $transactionPaths = Get-SystemV7MetaTransactionPaths -ProjectPath $faultFixture.Project
        $pendingTransactions = @(Get-ChildItem -LiteralPath $transactionPaths.Pending -Directory -Force -ErrorAction SilentlyContinue)
        if ($pendingTransactions.Count -ne 0) { throw "LEGACY_REOPEN_ROLLBACK_PENDING_TRANSACTION: $faultPoint" }
        if ($faultPoint -ceq 'AFTER_META_WRITE') {
            $abortedTransactions = @(Get-ChildItem -LiteralPath $transactionPaths.Conflicts -Directory -Force -ErrorAction SilentlyContinue)
            if ($abortedTransactions.Count -ne 1 -or -not (Test-Path -LiteralPath (Join-Path $abortedTransactions[0].FullName 'ABORTED.json') -PathType Leaf)) {
                throw 'LEGACY_REOPEN_ROLLBACK_ABORT_AUDIT_MISSING: AFTER_META_WRITE'
            }
        }
    }

    # Retry z identycznym, wcześniejszym receiptem nie może usunąć tego receiptu,
    # jeżeli późniejsza próba zakończy się błędem.
    $existingReceiptFixture = New-K4ReopenFixture -Name 'fixture-k4-existing-receipt'
    $existingMetaBytes = [IO.File]::ReadAllBytes($existingReceiptFixture.MetaPath)
    $existingScope = 'Akt 6: test zachowania wcześniejszego identycznego receiptu.'
    $fixedCreatedAtUtc = '2026-09-02T12:00:00.0000000+00:00'
    $seedResult = Invoke-SystemV7LegacyStageReopen -ProjectPath $existingReceiptFixture.Project -TargetStage K2B -ReasonCode ARCHITECTURE_CONFLICT -Scope $existingScope -InternalTestCreatedAtUtc $fixedCreatedAtUtc
    $restoreMap = @(
        [pscustomobject]@{ Archive='k3-pakiety'; Active='_work\k3-pakiety'; Directory=$true },
        [pscustomobject]@{ Archive='canonical\03-draft.md'; Active='03-draft.md'; Directory=$false },
        [pscustomobject]@{ Archive='canonical\04-raport-qa.md'; Active='04-raport-qa.md'; Directory=$false },
        [pscustomobject]@{ Archive='canonical\04B-fact-check.md'; Active='04B-fact-check.md'; Directory=$false },
        [pscustomobject]@{ Archive='qa-baseline.md'; Active='_work\qa-baseline.md'; Directory=$false },
        [pscustomobject]@{ Archive='qa-baseline.receipt.json'; Active='_work\qa-baseline.receipt.json'; Directory=$false },
        [pscustomobject]@{ Archive='K4'; Active='_work\K4'; Directory=$true }
    )
    foreach ($restore in $restoreMap) {
        $archiveItem = Join-Path $seedResult.ArchivePath $restore.Archive
        $activeItem = Join-Path $existingReceiptFixture.Project $restore.Active
        [IO.Directory]::CreateDirectory((Split-Path -Parent $activeItem)) | Out-Null
        if ($restore.Directory) { [IO.Directory]::Move($archiveItem,$activeItem) }
        else { [IO.File]::Move($archiveItem,$activeItem) }
    }
    [IO.Directory]::Delete($seedResult.ArchivePath,$true)
    [IO.File]::WriteAllBytes($existingReceiptFixture.MetaPath,$existingMetaBytes)
    $existingReceiptHash = (Get-FileHash -LiteralPath $seedResult.ReceiptPath -Algorithm SHA256).Hash
    $beforeExistingReceiptFault = @(Get-FixtureTreeManifest -Root $existingReceiptFixture.Project)
    $existingReceiptFaultObserved = $false
    try {
        Invoke-SystemV7LegacyStageReopen -ProjectPath $existingReceiptFixture.Project -TargetStage K2B -ReasonCode ARCHITECTURE_CONFLICT -Scope $existingScope -InternalTestFaultPoint AFTER_RECEIPT -InternalTestCreatedAtUtc $fixedCreatedAtUtc | Out-Null
    } catch {
        if ($_.Exception.Message -cne 'LEGACY_REOPEN_TEST_FAULT_AFTER_RECEIPT') { throw }
        $existingReceiptFaultObserved = $true
    }
    if (-not $existingReceiptFaultObserved) { throw 'LEGACY_REOPEN_EXISTING_RECEIPT_FAULT_NOT_OBSERVED' }
    $afterExistingReceiptFault = @(Get-FixtureTreeManifest -Root $existingReceiptFixture.Project)
    Assert-FixtureTreeIdentity -Before $beforeExistingReceiptFault -After $afterExistingReceiptFault -Label 'EXISTING_RECEIPT'
    if (-not (Test-Path -LiteralPath $seedResult.ReceiptPath -PathType Leaf) -or (Get-FileHash -LiteralPath $seedResult.ReceiptPath -Algorithm SHA256).Hash -cne $existingReceiptHash) {
        throw 'LEGACY_REOPEN_EXISTING_RECEIPT_NOT_PRESERVED'
    }

    [pscustomobject]@{
        Status='PASS'
        ProjectPath=$project
        ReceiptSha256=$result.ReceiptSha256
        ArchivedItems=$result.ArchivedItems
        StateReceiptValid=$head.Valid
        SourcePreserved=$true
        CanonicalK0K1K2Preserved=$true
        K4ToK2B='PASS'
        K4ReceiptSha256=$resultK4.ReceiptSha256
        K4ArchivedItems=$resultK4.ArchivedItems
        K4StateValidation='PASS'
        RollbackFaultPoints='PASS'
        ExistingReceiptRollback='PASS'
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
        $resolvedSystemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolvedTemp.StartsWith($resolvedSystemTemp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolvedTemp) -notmatch '^system-v7-legacy-reopen-[a-f0-9]{32}$') {
            throw "FIXTURE_CLEANUP_PATH_UNSAFE: $resolvedTemp"
        }
        [IO.Directory]::Delete($resolvedTemp,$true)
    }
}
