param(
    [Parameter(Mandatory)][string]$SystemRoot,
    [Parameter(Mandatory)][string]$FixtureRoot
)

$ErrorActionPreference = 'Stop'
$systemRoot = [IO.Path]::GetFullPath($SystemRoot)
. (Join-Path $systemRoot 'tools\Narrative-V2.ps1')

$caseRoot = Join-Path $systemRoot '_SYSTEM\NARRATIVE\TEST-FIXTURES\SEMANTIC-LENSES'
$caseManifest = Get-Content -LiteralPath (Join-Path $caseRoot 'case-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 32
if ([string]$caseManifest.schema -cne 'SYSTEM_V7_SEMANTIC_LENS_CASE_MANIFEST_V1') { throw 'SEMANTIC_PREFLIGHT_CASE_MANIFEST_INVALID' }

function Get-CaseRecord([string]$CaseId) {
    $records = @($caseManifest.cases | Where-Object { [string]$_.case_id -ceq $CaseId })
    if ($records.Count -ne 1) { throw "SEMANTIC_PREFLIGHT_CASE_NOT_FOUND: $CaseId" }
    $path = Join-Path $caseRoot ([string]$records[0].primary_fixture_relative)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne [string]$records[0].primary_fixture_sha256) {
        throw "SEMANTIC_PREFLIGHT_CASE_HASH_INVALID: $CaseId"
    }
    [pscustomobject]@{ Record=$records[0]; Text=(Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim() }
}

$exemplarCase = Get-CaseRecord 'EDITOR-EXEMPLAR-COPY-001'
$exemplarSpec = @($exemplarCase.Record.support_fixtures | Where-Object { [string]$_.purpose -ceq 'VOICE_EXEMPLAR_PHRASE' })
if ($exemplarSpec.Count -ne 1) { throw 'SEMANTIC_PREFLIGHT_EXEMPLAR_SPEC_INVALID' }
$exemplarPath = Join-Path $caseRoot ([string]$exemplarSpec[0].relative)
if ((Get-FileHash -LiteralPath $exemplarPath -Algorithm SHA256).Hash -cne [string]$exemplarSpec[0].sha256) { throw 'SEMANTIC_PREFLIGHT_EXEMPLAR_HASH_INVALID' }
$voiceExemplars = Get-Content -LiteralPath $exemplarPath -Raw -Encoding UTF8
$directCase = Get-CaseRecord 'EDITOR-DIRECT-CONTACT-NO-VC-001'
$humorCase = Get-CaseRecord 'EDITOR-HUMOR-FORBIDDEN-001'

$architecture = [pscustomobject]@{
    architecture_revision = 'SEMANTIC-PREFLIGHT-REGRESSION-V1'
    acts = @([pscustomobject]@{ act_id='ACT-001'; humor_mode='FORBIDDEN' })
}
$draftSha = 'A' * 64
$results = [Collections.Generic.List[object]]::new()

function Invoke-PreflightCase {
    param(
        [string]$Name,
        [string]$Prose,
        [string[]]$NarrativeRefs,
        [bool]$ExpectedValid,
        [string[]]$ExpectedRules,
        [string]$ExpectedError = ''
    )
    $state = Get-SystemV7NarrativeSemanticPreflightState -ArchitectureData $architecture -Blocks @(
        [pscustomobject]@{ act_id='ACT-001'; block_id='BLOCK-ACT-001-001'; prose=$Prose; narrative_refs=@($NarrativeRefs) }
    ) -VoiceExemplarsText $voiceExemplars -DraftSha256 $draftSha
    $actualRules = @($state.Data.findings | ForEach-Object { [string]$_.rule_id } | Sort-Object)
    $expectedSorted = @($ExpectedRules | Sort-Object)
    $rulesMatch = ($actualRules -join '|') -ceq ($expectedSorted -join '|')
    $errorFound = if ([string]::IsNullOrWhiteSpace($ExpectedError)) { $state.Errors.Count -eq 0 } else { @($state.Errors | Where-Object { $_ -like "$ExpectedError*" }).Count -gt 0 }
    $pass = [bool]$state.Valid -eq $ExpectedValid -and [bool]$state.GateReady -eq $ExpectedValid -and $rulesMatch -and $errorFound
    $results.Add([pscustomobject]@{
        Case=$Name; ExpectedValid=$ExpectedValid; ActualValid=[bool]$state.Valid; ActualGateReady=[bool]$state.GateReady
        ExpectedRules=$expectedSorted; ActualRules=$actualRules; ExpectedError=$ExpectedError; Errors=@($state.Errors); Pass=$pass
    })
}

Invoke-PreflightCase -Name 'neutral-no-alert' -Prose 'Badacze porównali dokument z katalogiem i zapisali wynik dalszego sprawdzenia.' -NarrativeRefs @() -ExpectedValid $true -ExpectedRules @()
Invoke-PreflightCase -Name 'exemplar-eight-gram-review-alert' -Prose $exemplarCase.Text -NarrativeRefs @() -ExpectedValid $true -ExpectedRules @('VOICE_EXEMPLAR_8GRAM_OVERLAP')
Invoke-PreflightCase -Name 'direct-contact-without-vc-review-alert' -Prose $directCase.Text -NarrativeRefs @() -ExpectedValid $true -ExpectedRules @('UNPLANNED_DIRECT_VIEWER_CONTACT')
Invoke-PreflightCase -Name 'direct-contact-with-vc-no-alert' -Prose $directCase.Text -NarrativeRefs @('VC-001') -ExpectedValid $true -ExpectedRules @()
Invoke-PreflightCase -Name 'humor-forbidden-hard-fail' -Prose $humorCase.Text -NarrativeRefs @() -ExpectedValid $false -ExpectedRules @('HUMOR_FORBIDDEN_CLEAR_SIGNAL') -ExpectedError 'HUMOR_FORBIDDEN_CLEAR_SIGNAL'

$failed = @($results | Where-Object { -not $_.Pass })
$result = [pscustomobject]@{
    FixturePath=$caseRoot
    NarrativeV2Sha256=(Get-FileHash -LiteralPath (Join-Path $systemRoot 'tools\Narrative-V2.ps1') -Algorithm SHA256).Hash
    Total=$results.Count
    Passed=$results.Count-$failed.Count
    Failed=$failed.Count
    FailedCases=@($failed.Case)
    Cases=@($results)
}
$result
if ($failed.Count -gt 0) { throw 'SEMANTIC_PREFLIGHT_REGRESSION_FAILED' }
