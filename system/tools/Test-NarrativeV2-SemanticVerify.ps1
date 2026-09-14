[CmdletBinding()]
param(
    [string]$CaseId = 'VERIFY-OVERCONFIDENCE-001',
    [string]$ProjectPath,
    [string]$OutputPath,
    [string]$RunReceiptPath,
    [switch]$AuditFakePass,
    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'
$systemRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')

$fixtureRoot = Join-Path $systemRoot '_SYSTEM\NARRATIVE\TEST-FIXTURES\SEMANTIC-LENSES'
$manifestPath = Join-Path $fixtureRoot 'case-manifest.json'

function Resolve-SemanticFixturePath {
    param([Parameter(Mandatory)][string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "SEMANTIC_FIXTURE_RELATIVE_PATH_INVALID: $Relative"
    }
    $root = [IO.Path]::GetFullPath($fixtureRoot).TrimEnd('\','/')
    $full = [IO.Path]::GetFullPath((Join-Path $root $Relative))
    if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "SEMANTIC_FIXTURE_PATH_OUTSIDE_ROOT: $Relative"
    }
    return $full
}

function Test-SemanticFixtureManifest {
    $errors = [Collections.Generic.List[string]]::new()
    $manifest = $null
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return [pscustomobject]@{ Valid=$false; Errors=@('SEMANTIC_CASE_MANIFEST_MISSING'); Data=$null }
    }
    try {
        $null = Assert-SystemV7TreeNoReparse -RootPath $fixtureRoot -ContainmentRoot $systemRoot
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 32
    } catch {
        return [pscustomobject]@{ Valid=$false; Errors=@("SEMANTIC_CASE_MANIFEST_UNREADABLE: $($_.Exception.Message)"); Data=$null }
    }
    $manifestFields = @('schema','revision','cases')
    if (@(Compare-Object -ReferenceObject $manifestFields -DifferenceObject @($manifest.PSObject.Properties.Name)).Count -gt 0 -or @($manifest.PSObject.Properties.Name).Count -ne $manifestFields.Count) {
        $errors.Add('SEMANTIC_CASE_MANIFEST_FIELDS_INVALID')
    }
    if ([string]$manifest.schema -cne 'SYSTEM_V7_SEMANTIC_LENS_CASE_MANIFEST_V1' -or [string]$manifest.revision -cne '2026-08-31.1') {
        $errors.Add('SEMANTIC_CASE_MANIFEST_SCHEMA_INVALID')
    }
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($caseRecord in @($manifest.cases)) {
        $caseFields = @('case_id','lens','primary_input_role','primary_fixture_relative','primary_fixture_sha256','support_fixtures','expected')
        if (@(Compare-Object -ReferenceObject $caseFields -DifferenceObject @($caseRecord.PSObject.Properties.Name)).Count -gt 0 -or @($caseRecord.PSObject.Properties.Name).Count -ne $caseFields.Count) {
            $errors.Add("SEMANTIC_CASE_FIELDS_INVALID: $([string]$caseRecord.case_id)")
            continue
        }
        $id = [string]$caseRecord.case_id
        if ($id -notmatch '^(?:VERIFY|EDITOR)-[A-Z0-9-]+-\d{3}$' -or -not $ids.Add($id)) {
            $errors.Add("SEMANTIC_CASE_ID_INVALID_OR_DUPLICATE: $id")
        }
        if ([string]$caseRecord.lens -notin @('VERIFY','EDITOR')) {
            $errors.Add("SEMANTIC_CASE_LENS_INVALID: $id")
        }
        foreach ($fileSpec in @(
            [pscustomobject]@{ relative=[string]$caseRecord.primary_fixture_relative; sha256=[string]$caseRecord.primary_fixture_sha256; purpose='PRIMARY' }
        ) + @($caseRecord.support_fixtures)) {
            try {
                $relative = [string]$fileSpec.relative
                $expectedSha = [string]$fileSpec.sha256
                $path = Resolve-SemanticFixturePath -Relative $relative
                if ($expectedSha -notmatch '^[A-F0-9]{64}$' -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
                    throw 'missing-or-invalid-sha'
                }
                $actualSha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
                if ($actualSha -cne $expectedSha) { throw "sha-mismatch/$actualSha" }
            } catch {
                $errors.Add("SEMANTIC_FIXTURE_INTEGRITY_INVALID: $id/$([string]$fileSpec.purpose)/$($_.Exception.Message)")
            }
        }
    }
    [pscustomobject]@{ Valid=$errors.Count -eq 0; Errors=@($errors); Data=$manifest }
}

function Add-SemanticMachineStatus {
    param([Parameter(Mandatory)][object]$Row)
    $copy = [ordered]@{}
    if ($Row -is [Collections.IDictionary]) {
        foreach ($key in $Row.Keys) { $copy[[string]$key] = $Row[$key] }
    } else {
        foreach ($property in $Row.PSObject.Properties) { $copy[$property.Name] = $property.Value }
    }
    $copy.status = 'PASS'
    return [pscustomobject]$copy
}

function Invoke-SemanticFakePassAudit {
    param([Parameter(Mandatory)][object]$CaseRecord)
    $auditErrors = [Collections.Generic.List[string]]::new()
    $tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
    $tempRoot = Join-Path $tempParent ('SystemV7-SemanticVerify-' + [guid]::NewGuid().ToString('N'))
    $parserState = $null
    try {
        $project = Join-Path $tempRoot 'project'
        $bundleRoot = Join-Path $project '_work\fake-bundle'
        [IO.Directory]::CreateDirectory($bundleRoot) | Out-Null
        $draftPath = Join-Path $bundleRoot 'DRAFT_BLOCKS.md'
        $locatorPath = Join-Path $bundleRoot 'SOURCE_LOCATORS.json'
        $sourceRoot = Join-Path $bundleRoot 'SOURCE_FILES'
        [IO.Directory]::CreateDirectory($sourceRoot) | Out-Null
        [IO.File]::Copy((Resolve-SemanticFixturePath -Relative ([string]$CaseRecord.primary_fixture_relative)), $draftPath, $false)
        $locatorSpec = @($CaseRecord.support_fixtures | Where-Object { [string]$_.purpose -ceq 'SOURCE_LOCATORS' })
        $sourceSpec = @($CaseRecord.support_fixtures | Where-Object { [string]$_.purpose -ceq 'SOURCE_UNCERTAINTY' })
        if ($locatorSpec.Count -ne 1 -or $sourceSpec.Count -ne 1) { throw 'FAKE_PASS_SUPPORT_FIXTURES_INVALID' }
        [IO.File]::Copy((Resolve-SemanticFixturePath -Relative ([string]$locatorSpec[0].relative)), $locatorPath, $false)
        $sourcePath = Join-Path $sourceRoot ([IO.Path]::GetFileName([string]$sourceSpec[0].relative))
        [IO.File]::Copy((Resolve-SemanticFixturePath -Relative ([string]$sourceSpec[0].relative)), $sourcePath, $false)
        $entry = {
            param([string]$Role,[string]$Path)
            [pscustomobject]@{
                content_role=$Role
                bundle_relative=Get-SystemV7NarrativeRelativePath -Root $project -Path $Path
                sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
            }
        }
        $bundle = [pscustomobject]@{ entries=@(
            (&$entry 'DRAFT_BLOCKS' $draftPath),
            (&$entry 'SOURCE_LOCATORS' $locatorPath),
            [pscustomobject]@{content_role='SOURCE_FILES';bundle_relative=(Get-SystemV7NarrativeRelativePath -Root $project -Path $sourceRoot);sha256=[string]$sourceSpec[0].sha256}
        ) }
        $inventory = Get-SystemV7K4BundleInventoryState -ProjectPath $project -Lens VERIFY -BundleData $bundle
        if (-not $inventory.Valid) { throw "FAKE_PASS_INVENTORY_INVALID: $($inventory.Errors -join '; ')" }
        $coverageLines = @($inventory.Coverage | ForEach-Object { 'COVERAGE_JSON: ' + ((Add-SemanticMachineStatus -Row $_) | ConvertTo-Json -Compress -Depth 16) })
        $locatorLines = @($inventory.Locators | ForEach-Object { 'LOCATOR_JSON: ' + ((Add-SemanticMachineStatus -Row $_) | ConvertTo-Json -Compress -Depth 16) })
        $draftSha = (Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash
        $fakeOutput = @"
SCHEMA: K4_VERIFY_OUTPUT_V1
LENS: VERIFY
DRAFT_SHA256: $draftSha
VERDICT: PASS
CRITICAL_COUNT: 0
MAJOR_COUNT: 0
MINOR_COUNT: 0
REVIEW_ALERT_COUNT: 0
## CLAIM_COVERAGE
$($coverageLines -join "`n")
ANALYSIS: Każdy blok oraz każda przypisana karta zostały rzekomo sprawdzone bez pominięcia zamkniętej mapy dowodowej.
## SOURCE_LOCATORS_CHECKED
$($locatorLines -join "`n")
ANALYSIS: Każda użyta karta ma podany identyfikator źródła i dokładny lokalizator prowadzący do właściwego fragmentu.
## ATTRIBUTION_UNCERTAINTY
Poziom pewności narracji rzekomo pozostaje zgodny z językiem źródła, mimo że treści faktycznie sobie przeczą.
## CONTRADICTIONS
Raport rzekomo nie wykrywa sprzeczności, chociaż źródło zachowuje hipotezę, a narracja ogłasza pewność.
## FINDINGS
BRAK
"@
        $output = Join-Path $project 'fake-pass-output.md'
        [IO.File]::WriteAllText($output, (ConvertTo-SystemV7LfText -Text $fakeOutput), [Text.UTF8Encoding]::new($false))
        $parserState = Get-SystemV7K4LensOutputState -ProjectPath $project -Lens VERIFY -OutputPath $output -ExpectedDraftSha256 $draftSha -BundleData $bundle
    } catch {
        $auditErrors.Add($_.Exception.Message)
    } finally {
        if (Test-Path -LiteralPath $tempRoot -PathType Container) {
            $resolved = [IO.Path]::GetFullPath($tempRoot)
            if (-not $resolved.StartsWith($tempParent + [IO.Path]::DirectorySeparatorChar + 'SystemV7-SemanticVerify-', [StringComparison]::OrdinalIgnoreCase)) {
                $auditErrors.Add('FAKE_PASS_TEMP_CLEANUP_TARGET_INVALID')
            } else {
                [IO.Directory]::Delete($resolved, $true)
            }
        }
    }
    $accepted = $null -ne $parserState -and [bool]$parserState.Valid -and [string]$parserState.Verdict -ceq 'PASS'
    [pscustomobject]@{
        Status=if($accepted){'EXPECTED_STRUCTURAL_LIMITATION_CONFIRMED'}else{'UNEXPECTED_PARSER_RESULT'}
        ParserAcceptedFakePass=$accepted
        SemanticPass=$false
        Meaning='Parser sprawdza zamknięty format, pokrycie i wiązania, ale nie zastępuje uczciwej oceny semantycznej modelu.'
        Errors=@($auditErrors)+@(if($parserState -and -not $parserState.Valid){$parserState.Errors}else{@()})
    }
}

function Get-VerifyFindingRecords {
    param([AllowEmptyString()][string]$Body)
    $records = [Collections.Generic.List[object]]::new()
    $pattern = '^FINDING:\s*(?<id>V-\d{3})\s*\|\s*SEVERITY:\s*(?<severity>CRITICAL|MAJOR|MINOR|REVIEW_ALERT)\s*\|\s*BLOCK_ID:\s*(?<block>BLOCK-ACT-\d{3}-\d{3})\s*\|\s*P_ID:\s*(?<p>#P-\d{3,}|BRAK)\s*\|\s*SOURCE_ID:\s*(?<source>\S.+?)\s*\|\s*LOCATOR:\s*(?<locator>\S.+?)\s*\|\s*OBSERVATION:\s*(?<observation>\S.+?)\s*\|\s*CLOSURE:\s*(?<closure>\S.+)$'
    foreach ($line in @($Body -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -cne 'BRAK' })) {
        $match = [regex]::Match($line, $pattern)
        if ($match.Success) {
            $records.Add([pscustomobject]@{
                Id=$match.Groups['id'].Value; Severity=$match.Groups['severity'].Value; BlockId=$match.Groups['block'].Value
                PId=$match.Groups['p'].Value; SourceId=$match.Groups['source'].Value.Trim(); Locator=$match.Groups['locator'].Value.Trim()
                Observation=$match.Groups['observation'].Value.Trim(); Closure=$match.Groups['closure'].Value.Trim(); Raw=$line
            })
        }
    }
    return @($records)
}

$manifestState = Test-SemanticFixtureManifest
$selectedCase = if ($manifestState.Valid) { @($manifestState.Data.cases | Where-Object { [string]$_.case_id -ceq $CaseId }) } else { @() }
$resultErrors = [Collections.Generic.List[string]]::new()
foreach ($problem in @($manifestState.Errors)) { $resultErrors.Add([string]$problem) }
if ($manifestState.Valid -and $selectedCase.Count -ne 1) { $resultErrors.Add("SEMANTIC_CASE_NOT_FOUND_OR_DUPLICATE: $CaseId") }
if ($selectedCase.Count -eq 1 -and [string]$selectedCase[0].lens -cne 'VERIFY') { $resultErrors.Add("SEMANTIC_VERIFY_REQUIRES_VERIFY_CASE: $CaseId") }

$fakeAudit = if ($AuditFakePass -and $selectedCase.Count -eq 1 -and [string]$selectedCase[0].lens -ceq 'VERIFY') {
    Invoke-SemanticFakePassAudit -CaseRecord $selectedCase[0]
} elseif ($AuditFakePass) {
    [pscustomobject]@{Status='NOT_RUN';ParserAcceptedFakePass=$false;SemanticPass=$false;Meaning='Wybrany przypadek nie jest przypadkiem VERIFY.';Errors=@('FAKE_PASS_AUDIT_CASE_INVALID')}
} else {
    [pscustomobject]@{Status='NOT_REQUESTED';ParserAcceptedFakePass=$false;SemanticPass=$false;Meaning='Uruchom z -AuditFakePass, aby fizycznie potwierdzić ograniczenie parsera.';Errors=@()}
}

$artifactParametersPresent = -not [string]::IsNullOrWhiteSpace($ProjectPath) -and -not [string]::IsNullOrWhiteSpace($OutputPath) -and -not [string]::IsNullOrWhiteSpace($RunReceiptPath)
$artifactFilesPresent = $artifactParametersPresent -and (Test-Path -LiteralPath $ProjectPath -PathType Container) -and (Test-Path -LiteralPath $OutputPath -PathType Leaf) -and (Test-Path -LiteralPath $RunReceiptPath -PathType Leaf)
$verdict = 'NOT_RUN'
$semanticPass = $false
$receiptValid = $false
$parserValid = $false
$bindingValid = $false
$matchedFinding = $null

if ($resultErrors.Count -gt 0) {
    $verdict = 'FAIL'
} elseif (-not $artifactFilesPresent) {
    if ($artifactParametersPresent) { $resultErrors.Add('REAL_VERIFY_PROJECT_OUTPUT_OR_RECEIPT_MISSING') }
} else {
    try {
        $caseRecord = $selectedCase[0]
        $project = [IO.Path]::GetFullPath($ProjectPath)
        $output = [IO.Path]::GetFullPath($OutputPath)
        $receiptPath = [IO.Path]::GetFullPath($RunReceiptPath)
        $null = Get-SystemV7NarrativeRelativePath -Root $project -Path $output
        $null = Get-SystemV7NarrativeRelativePath -Root $project -Path $receiptPath
        $receipt = Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $receiptPath -ExpectedRunType VERIFY -RequireLiveInputs
        $receiptValid = [bool]$receipt.Valid
        if (-not $receipt.Valid) { throw "REAL_VERIFY_RECEIPT_INVALID: $($receipt.Errors -join '; ')" }
        $expectedOutput = [IO.Path]::GetFullPath((Join-Path $project ([string]$receipt.Data.output_relative)))
        if (-not $expectedOutput.Equals($output, [StringComparison]::OrdinalIgnoreCase)) { throw 'REAL_VERIFY_OUTPUT_PATH_RECEIPT_MISMATCH' }
        $bundlePath = Join-Path $project ([string]$receipt.Data.input_manifest_relative)
        $bundle = Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $bundlePath -RequireLiveSource
        if (-not $bundle.Valid) { throw "REAL_VERIFY_BUNDLE_INVALID: $($bundle.Errors -join '; ')" }
        $primary = @($bundle.Data.entries | Where-Object { [string]$_.content_role -ceq [string]$caseRecord.primary_input_role })
        if ($primary.Count -ne 1 -or [string]$primary[0].sha256 -cne [string]$caseRecord.primary_fixture_sha256) { throw 'REAL_VERIFY_PRIMARY_FIXTURE_BINDING_MISMATCH' }
        $sourceSpec = @($caseRecord.support_fixtures | Where-Object { [string]$_.purpose -ceq 'SOURCE_UNCERTAINTY' })
        $sourceEntry = @($bundle.Data.entries | Where-Object { [string]$_.content_role -ceq 'SOURCE_FILES' })
        if ($sourceSpec.Count -ne 1 -or $sourceEntry.Count -ne 1 -or @($sourceEntry[0].files | Where-Object { [string]$_.sha256 -ceq [string]$sourceSpec[0].sha256 }).Count -ne 1) {
            throw 'REAL_VERIFY_SOURCE_FIXTURE_BINDING_MISMATCH'
        }
        $locatorEntry = @($bundle.Data.entries | Where-Object { [string]$_.content_role -ceq 'SOURCE_LOCATORS' })
        if ($locatorEntry.Count -ne 1) { throw 'REAL_VERIFY_LOCATOR_ROLE_INVALID' }
        $locatorData = Get-Content -LiteralPath (Join-Path $project ([string]$locatorEntry[0].bundle_relative)) -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 16
        $expected = $caseRecord.expected
        $locatorMatches = @($locatorData.cards | Where-Object {
            [string]$_.p_id -ceq [string]$expected.p_id -and [string]$_.source_id -ceq [string]$expected.source_id -and [string]$_.locator -ceq [string]$expected.locator
        })
        if ($locatorMatches.Count -ne 1) { throw 'REAL_VERIFY_LOCATOR_FIXTURE_BINDING_MISMATCH' }
        $draftIdentity = Get-SystemV7K4BundleDraftIdentityState -Lens VERIFY -BundleData $bundle.Data
        if (-not $draftIdentity.Valid) { throw 'REAL_VERIFY_DRAFT_IDENTITY_INVALID' }
        $lensState = Get-SystemV7K4LensOutputState -ProjectPath $project -Lens VERIFY -OutputPath $output -ExpectedDraftSha256 $draftIdentity.Sha256 -BundleData $bundle.Data
        $parserValid = [bool]$lensState.Valid
        if (-not $lensState.Valid) { throw "REAL_VERIFY_OUTPUT_INVALID: $($lensState.Errors -join '; ')" }
        $bindingValid = $true
        $records = @(Get-VerifyFindingRecords -Body ([string]$lensState.Sections.FINDINGS))
        $candidates = @($records | Where-Object {
            [string]$_.BlockId -ceq [string]$expected.block_id -and [string]$_.PId -ceq [string]$expected.p_id -and
            [string]$_.SourceId -ceq [string]$expected.source_id -and [string]$_.Locator -ceq [string]$expected.locator -and
            [string]$_.Severity -in @('CRITICAL','MAJOR')
        })
        foreach ($candidate in $candidates) {
            $semanticText = [string]$candidate.Observation + ' ' + [string]$candidate.Closure
            if ($semanticText -match [string]$expected.certainty_regex -and $semanticText -match [string]$expected.uncertainty_regex) {
                $matchedFinding = $candidate
                break
            }
        }
        if ([string]$lensState.Verdict -cne [string]$expected.verdict) { throw 'REAL_VERIFY_EXPECTED_FAIL_VERDICT_MISSING' }
        if ($null -eq $matchedFinding) { throw 'REAL_VERIFY_EXACT_SEMANTIC_FINDING_MISSING' }
        $semanticPass = $true
        $verdict = 'PASS'
    } catch {
        $resultErrors.Add($_.Exception.Message)
        $verdict = 'FAIL'
    }
}

$result = [pscustomobject]@{
    Schema='SYSTEM_V7_SEMANTIC_VERIFY_RESULT_V1'
    CaseId=$CaseId
    Verdict=$verdict
    SemanticPass=$semanticPass
    FixtureIntegrityValid=[bool]$manifestState.Valid
    RealOutputAndReceiptPresent=$artifactFilesPresent
    ReceiptValid=$receiptValid
    ParserValid=$parserValid
    CaseBindingValid=$bindingValid
    ExactFindingMatched=($null -ne $matchedFinding)
    MatchedFinding=$matchedFinding
    FakePassAudit=$fakeAudit
    Errors=@($resultErrors)
    Instruction=if($verdict -ceq 'NOT_RUN'){'Dostarcz -ProjectPath, -OutputPath i -RunReceiptPath ze świeżego, rzeczywistego przebiegu VERIFY. NOT_RUN nie jest PASS.'}else{'Wynik odnosi się wyłącznie do wskazanego, kryptograficznie związanego przypadku.'}
}

$result
if (-not $NoExit) {
    if ($verdict -ceq 'FAIL') { exit 1 }
    if ($verdict -ceq 'NOT_RUN') { exit 2 }
}
