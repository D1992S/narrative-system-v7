param(
    [Parameter(Mandatory)][string]$SystemRoot,
    [Parameter(Mandatory)][string]$ProjectPath
)
$ErrorActionPreference='Stop'
$systemRoot=[IO.Path]::GetFullPath($SystemRoot)
. (Join-Path $systemRoot 'tools\Narrative-Receipts.ps1')
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$packetPath=Join-Path $ProjectPath '_work\k3\packets\ACT-001.act-packet.json'
$ledgerPath=Join-Path $ProjectPath '_work\k3\packets\ACT-001.constraint-ledger.json'
$packet=Get-Content -LiteralPath $packetPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
$ledger=Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64

function Copy-Value([object]$Value){
    (ConvertTo-SystemV7CanonicalJson -Value $Value)|ConvertFrom-Json -DateKind String -Depth 64
}
function New-Constraint([string]$Cid,[string]$Source,[string[]]$Objects,[string]$Action='Wykonaj dokładnie jeden obowiązek atomowy'){
    if($Action -ceq 'Wykonaj dokładnie jeden obowiązek atomowy' -and $Objects.Count -gt 1){
        if($Source -ceq 'ACT_FUNCTION'){$Action='Zrealizuj funkcję aktu, zmianę stanu i most, a completion potraktuj jako kryterium odbioru tej samej transformacji'}
        elseif($Source -ceq 'SW'){$sw=@($Objects|Where-Object{$_ -match '^SW:'})[0].Substring(3);$Action="Wykonaj jednostkę $sw z kompletem przypisanych dowodów"}
        elseif($Source -ceq 'NR'){$nr=([regex]::Match((@($Objects|Where-Object{$_ -match '^NR:SETUP:'})[0]),'^NR:SETUP:(NR-\d{3})$')).Groups[1].Value;$Action="Wykonaj przygotowanie $nr z przypisanym embargiem"}
    }
    [pscustomobject][ordered]@{cid=$Cid;source_field=$Source;action=$Action;object_ids=@($Objects);why_hard='Bez tego kontrakt aktu jest niepełny';atomicity_reason='Jeden niezależny obowiązek wykonawczy';verification='Sprawdź dokładny ślad obowiązku'}
}
$results=[Collections.Generic.List[object]]::new()
function Assert-State([string]$Name,[object]$Packet,[object]$Ledger,[bool]$ExpectedValid,[string[]]$ExpectedErrors=@()){
    $state=Get-SystemV7ConstraintAtomicityState -Packet $Packet -Ledger $Ledger
    $ok=($state.Valid -eq $ExpectedValid)
    foreach($expected in $ExpectedErrors){if(-not @($state.Errors|Where-Object{[string]$_ -like $expected}).Count){$ok=$false}}
    $script:results.Add([pscustomobject]@{Case=$Name;Pass=$ok;Valid=$state.Valid;AtomicCount=$state.AtomicCount;Unbundled=$state.UnbundledConstraintCount;Errors=@($state.Errors)})
    if(-not $ok){throw "ATOMICITY_ASSERT_FAILED: $Name :: $($state.Errors -join '; ')"}
}

Assert-State -Name 'BASELINE_6_ATOMS' -Packet $packet -Ledger $ledger -ExpectedValid $true

foreach($case in @(
    [pscustomobject]@{Name='ACTION_TWO_COMMANDS_ORAZ';Action='Ujawnij prawdę oraz pokaż skutek'},
    [pscustomobject]@{Name='ACTION_TWO_COMMANDS_ONE_COMMA';Action='Ujawnij prawdę, pokaż skutek'},
    [pscustomobject]@{Name='ACTION_THREE_COMMANDS_TWO_COMMAS';Action='Ujawnij prawdę, pokaż skutek, domknij pytanie'},
    [pscustomobject]@{Name='ACTION_TWO_COMMANDS_SLASH';Action='Ujawnij prawdę / pokaż skutek'}
)){
    $p=Copy-Value $packet;$l=Copy-Value $ledger;$l.constraints[0].action=$case.Action
    Assert-State -Name $case.Name -Packet $p -Ledger $l -ExpectedValid $false -ExpectedErrors @('ATOMIC_CID_ACTION_CLOSED_FORM_INVALID: CID-001')
}

$threeCommands='Ujawnij prawdę, pokaż skutek, domknij pytanie'
$p=Copy-Value $packet;$l=Copy-Value $ledger;$p.act_function=$threeCommands
Assert-State -Name 'PACKET_ACT_FUNCTION_THREE_COMMANDS' -Packet $p -Ledger $l -ExpectedValid $false -ExpectedErrors @('ATOMIC_ACT_FIELD_NOT_SINGLE_PURPOSE: act_function')
$p=Copy-Value $packet;$l=Copy-Value $ledger;$p.scene_contracts[0].function=$threeCommands
Assert-State -Name 'SCENE_FUNCTION_THREE_COMMANDS' -Packet $p -Ledger $l -ExpectedValid $false -ExpectedErrors @('ATOMIC_SCENE_FIELD_NOT_SINGLE_PURPOSE: SW-001/function')
$p=Copy-Value $packet;$l=Copy-Value $ledger;$p.completion_criteria=@($threeCommands)
Assert-State -Name 'COMPLETION_THREE_COMMANDS' -Packet $p -Ledger $l -ExpectedValid $false -ExpectedErrors @('ATOMIC_COMPLETION_COUNT_OR_FORM_INVALID: 1','ATOMIC_COMPLETION_LIST_LIKE: 1')

$p=Copy-Value $packet;$l=Copy-Value $ledger
$p.scene_contracts[0].required_p=@('#P-001','#P-004')
$l.constraints[1].object_ids=@('SW:SW-001','REQUIRED:SW-001/#P-001','REQUIRED:SW-001/#P-004')
Assert-State -Name 'LEGAL_SAME_SW_MULTIPLE_CARDS' -Packet $p -Ledger $l -ExpectedValid $true

$p=Copy-Value $packet;$l=Copy-Value $ledger
$p.nq_actions=@('OPEN:NQ-001','OPEN:NQ-002')
$base=@($l.constraints[0..4]);$base+=$(New-Constraint 'CID-006' 'NQ' @('NQ:OPEN:NQ-001'))
$base+=$(New-Constraint 'CID-007' 'NQ' @('NQ:OPEN:NQ-002'))
$base+=$(New-Constraint 'CID-008' 'CONTINUITY_OUT' @('CONTINUITY_OUT:ACT-001'))
$l.constraints=@($base);$l.actual_total=8
Assert-State -Name 'MORE_THAN_7_CLOSED_ATOMS' -Packet $p -Ledger $l -ExpectedValid $false -ExpectedErrors @('ATOMIC_CONSTRAINT_COUNT_INVALID: 8')

$p=Copy-Value $packet;$l=Copy-Value $ledger
$p.nr_actions=@('SETUP:NR-001')
$p.do_not_reveal=@('NR-001 przed SW-002; NR-002 przed SW-003; NR-003 przed SW-004; NR-004 przed SW-005; NR-005 przed SW-006; NR-006 przed SW-007; NR-007 przed SW-008; NR-008 przed SW-009')
$base=@($l.constraints[0..4]);$base+=$(New-Constraint 'CID-006' 'NR' @('NR:SETUP:NR-001','DO_NOT_REVEAL:001'))
$base+=$(New-Constraint 'CID-007' 'CONTINUITY_OUT' @('CONTINUITY_OUT:ACT-001'))
$l.constraints=@($base);$l.actual_total=7
Assert-State -Name 'EIGHT_EMBARGOS_HIDDEN_IN_ONE_LIST_CID' -Packet $p -Ledger $l -ExpectedValid $false -ExpectedErrors @('ATOMIC_EMBARGO_FORMAT_INVALID: DO_NOT_REVEAL:001','ATOMIC_CID_BUNDLES_INDEPENDENT_ACTIONS: CID-006')

$p=Copy-Value $packet;$l=Copy-Value $ledger
$p.completion_criteria=@('Wykonaj obowiązek A; wykonaj obowiązek B; wykonaj obowiązek C; wykonaj obowiązek D')
Assert-State -Name 'FOUR_OBLIGATIONS_HIDDEN_IN_COMPLETION' -Packet $p -Ledger $l -ExpectedValid $false -ExpectedErrors @('ATOMIC_COMPLETION_LIST_LIKE: 1')

$p=Copy-Value $packet;$l=Copy-Value $ledger
$p.nr_actions=@('REVEAL:NR-001','CONSEQUENCE:NR-001')
$base=@($l.constraints[0..4]);$base+=$(New-Constraint 'CID-006' 'NR' @('NR:REVEAL:NR-001','NR:CONSEQUENCE:NR-001'))
$base+=$(New-Constraint 'CID-007' 'CONTINUITY_OUT' @('CONTINUITY_OUT:ACT-001'))
$l.constraints=@($base);$l.actual_total=7
Assert-State -Name 'REVEAL_AND_CONSEQUENCE_BUNDLED' -Packet $p -Ledger $l -ExpectedValid $false -ExpectedErrors @('ATOMIC_CID_BUNDLES_INDEPENDENT_ACTIONS: CID-006')

$p=Copy-Value $packet;$l=Copy-Value $ledger
$l.constraints[0].object_ids=@('ACT_FUNCTION:ACT-001','VIEWER_STATE:ACT-001','COMPLETION:001')
Assert-State -Name 'MISSING_BRIDGE_OBJECT' -Packet $p -Ledger $l -ExpectedValid $false -ExpectedErrors @('ATOMIC_REQUIRED_OBJECT_MISSING: BRIDGE:ACT-001')

$p=Copy-Value $packet;$l=Copy-Value $ledger;$p.humor_mode='FORBIDDEN'
Assert-State -Name 'FORBIDDEN_HUMOR_WITHOUT_CID' -Packet $p -Ledger $l -ExpectedValid $false -ExpectedErrors @('ATOMIC_REQUIRED_OBJECT_MISSING: HUMOR_MODE:ACT-001')

$p=Copy-Value $packet;$l=Copy-Value $ledger;$p.narrator_mode='FIRST_PERSON'
Assert-State -Name 'NONDEFAULT_NARRATOR_WITHOUT_CID' -Packet $p -Ledger $l -ExpectedValid $false -ExpectedErrors @('ATOMIC_REQUIRED_OBJECT_MISSING: NARRATOR_MODE:ACT-001')

$p=Copy-Value $packet;$l=Copy-Value $ledger
$l.constraints=@($l.constraints[0..4]);$l.actual_total=5
Assert-State -Name 'CONTINUITY_OUT_WITHOUT_CID' -Packet $p -Ledger $l -ExpectedValid $false -ExpectedErrors @('ATOMIC_REQUIRED_OBJECT_MISSING: CONTINUITY_OUT:ACT-001','ATOMIC_CONTINUITY_COUNT_INVALID: 0')

$manifestPath=Join-Path $ProjectPath '_work\narrative-runs\PREFLIGHT.ACT001.0001\input-manifest.json'
$bundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $ProjectPath -ManifestPath $manifestPath -RequireLiveSource
if(-not $bundle.Valid){throw "PREFLIGHT_BUNDLE_INVALID: $($bundle.Errors -join '; ')"}
$fakeOutput=Join-Path $ProjectPath '_work\test-outputs\fake-preflight-pass.md'
$fakeText="VERDICT: PASS`nUNBUNDLED_CONSTRAINT_COUNT: 0`nMISSING_ACTIONS: BRAK`nBUNDLED_ACTIONS: BRAK`nCONFLICTS: BRAK`nREASON: Model deklaruje przejście mimo niezgodnego licznika atomów.`n"
[IO.File]::WriteAllText($fakeOutput,$fakeText,[Text.UTF8Encoding]::new($false))
$fakeState=Get-SystemV7ConstraintPreflightOutputState -ProjectPath $ProjectPath -OutputPath $fakeOutput -BundleData $bundle.Data
$fakeOk=(-not $fakeState.Valid) -and @($fakeState.Errors|Where-Object{[string]$_ -like 'CONSTRAINT_PREFLIGHT_UNBUNDLED_COUNT_MISMATCH*'}).Count -gt 0
$results.Add([pscustomobject]@{Case='FAKE_MODEL_PASS_COUNT_ZERO';Pass=$fakeOk;Valid=$fakeState.Valid;AtomicCount=$null;Unbundled=$null;Errors=@($fakeState.Errors)})
if(-not $fakeOk){throw "FAKE_MODEL_PASS_NOT_REJECTED: $($fakeState.Errors -join '; ')"}

[pscustomobject]@{
    ProjectPath=$ProjectPath
    NarrativeV2Sha256=(Get-FileHash -LiteralPath (Join-Path $systemRoot 'tools\Narrative-V2.ps1') -Algorithm SHA256).Hash
    NarrativeReceiptsSha256=(Get-FileHash -LiteralPath (Join-Path $systemRoot 'tools\Narrative-Receipts.ps1') -Algorithm SHA256).Hash
    Cases=@($results)
    Passed=@($results|Where-Object Pass).Count
    Total=$results.Count
}
