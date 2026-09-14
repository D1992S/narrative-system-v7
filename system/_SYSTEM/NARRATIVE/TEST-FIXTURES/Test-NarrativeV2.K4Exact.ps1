param(
    [Parameter(Mandatory)][string]$SystemRoot,
    [Parameter(Mandatory)][string]$FixtureRoot
)
$ErrorActionPreference = 'Stop'

$systemRoot = [IO.Path]::GetFullPath($SystemRoot)
$tools = Join-Path $systemRoot 'tools'
. (Join-Path $tools 'Narrative-Receipts.ps1')

$fixtureRoot = [IO.Path]::GetFullPath($FixtureRoot)
$project = Join-Path $fixtureRoot 'project'
$bundleRoot = Join-Path $project '_work\qa-bundle'
$outputRoot = Join-Path $project '_work\qa-output'
[IO.Directory]::CreateDirectory($bundleRoot) | Out-Null
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$draftSha = 'A' * 64

function Write-Utf8Lf([string]$Path, [string]$Text) {
    $value = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $value.EndsWith("`n")) { $value += "`n" }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $value, [Text.UTF8Encoding]::new($false))
}

function Copy-Data($Value) {
    return ($Value | ConvertTo-Json -Depth 64 -Compress | ConvertFrom-Json -DateKind String -Depth 64)
}

function New-Entry([string]$Role, [string]$Path) {
    $relative = Get-SystemV7NarrativeRelativePath -Root $project -Path $Path
    [pscustomobject]@{
        content_role = $Role
        bundle_relative = $relative
        source_relative = $relative
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
}

$blockMap = [ordered]@{
    schema = 'K3_BLOCK_MAP_V1'
    prefix_sha256 = 'B' * 64
    model_id = 'gpt-test'
    model_revision = 'checkpoint-1'
    acts = @(
        [ordered]@{
            act_id='ACT-001';prose_sha256=('1'*64);blocks_sha256=('2'*64);attest_sha256=('3'*64)
            blocks=@(
                [ordered]@{block_id='BLOCK-ACT-001-001';block_sha256=('4'*64);word_count=20;trace_refs=@('SW-001');sw_ids=@('SW-001');source_p_ids=@('#P-001');narrative_refs=@('OPEN:NQ-001','VC-001')},
                [ordered]@{block_id='BLOCK-ACT-001-002';block_sha256=('5'*64);word_count=20;trace_refs=@('SW-002');sw_ids=@('SW-002');source_p_ids=@('#P-002');narrative_refs=@('PAY:NQ-001','SETUP:NR-001')}
            )
        },
        [ordered]@{
            act_id='ACT-002';prose_sha256=('6'*64);blocks_sha256=('7'*64);attest_sha256=('8'*64)
            blocks=@(
                [ordered]@{block_id='BLOCK-ACT-002-001';block_sha256=('9'*64);word_count=20;trace_refs=@('SW-003');sw_ids=@('SW-003');source_p_ids=@('#P-003','#P-004');narrative_refs=@('OPEN:NQ-002','REVEAL:NR-001','VC-002')},
                [ordered]@{block_id='BLOCK-ACT-002-002';block_sha256=('A'*64);word_count=20;trace_refs=@('SW-004');sw_ids=@('SW-004');source_p_ids=@('#P-005');narrative_refs=@('PAY:NQ-002','CONSEQUENCE:NR-001')}
            )
        }
    )
}

$questions = @(
    [ordered]@{nq_id='NQ-001';question='Pierwsze pytanie';opened_at='SW-001';why_care='Zmienia rozumienie';expected_form='ANSWER';payoff_node='SW-002';status='CLOSED'},
    [ordered]@{nq_id='NQ-002';question='Drugie pytanie';opened_at='SW-003';why_care='Domyka finał';expected_form='ANSWER';payoff_node='SW-004';status='CLOSED'}
)
$reveals = @(
    [ordered]@{nr_id='NR-001';reveal='Kluczowy reveal';evidence_p_ids=@('#P-003','#P-004');earliest_legal_node='SW-003';target_node='SW-003';setup_required='Zbuduj kontekst przed ujawnieniem';do_not_reveal_before='SW-003';consequence='Zmienia model widza';uncertainty_form='Jawnie zachowaj niepewność'}
)
$viewerContacts = @(
    [ordered]@{vc_id='VC-001';node='SW-001';function='ORIENT';level='MICRO';purpose='Ustawia punkt widzenia';risk='Nie zdradza finału';author_text='BRAK';approval='NOT_REQUIRED';approval_receipt_relative='BRAK';approval_receipt_sha256='BRAK'},
    [ordered]@{vc_id='VC-002';node='SW-003';function='RECALL';level='STRUCTURAL';purpose='Przypomina obietnicę';risk='Nie powtarza ekspozycji';author_text='BRAK';approval='NOT_REQUIRED';approval_receipt_relative='BRAK';approval_receipt_sha256='BRAK'}
)
$sceneWeave = @(
    [ordered]@{sw_id='SW-001';act_id='ACT-001';required_evidence=@([ordered]@{p_id='#P-001';function='Otwiera problem';necessity='Bez karty brak podstawy'})},
    [ordered]@{sw_id='SW-002';act_id='ACT-001';required_evidence=@([ordered]@{p_id='#P-002';function='Wypłaca pytanie';necessity='Bez karty brak odpowiedzi'})},
    [ordered]@{sw_id='SW-003';act_id='ACT-002';required_evidence=@([ordered]@{p_id='#P-003';function='Pierwsza część revealu';necessity='Wymagany dowód'},[ordered]@{p_id='#P-004';function='Druga część revealu';necessity='Wymagany dowód'})},
    [ordered]@{sw_id='SW-004';act_id='ACT-002';required_evidence=@([ordered]@{p_id='#P-005';function='Domyka konsekwencję';necessity='Wymagany finał'})}
)
$acts = @(
    [ordered]@{act_id='ACT-001';scene_weave_ids=@('SW-001','SW-002');state_change_evidence='SW-002'},
    [ordered]@{act_id='ACT-002';scene_weave_ids=@('SW-003','SW-004');state_change_evidence='SW-004'}
)
$architecture = [ordered]@{questions=$questions;reveals=$reveals;viewer_contacts=$viewerContacts;scene_weave=$sceneWeave;acts=$acts}

$blockMapPath = Join-Path $bundleRoot 'BLOCK_MAP.json'
Write-Utf8Lf -Path $blockMapPath -Text (ConvertTo-SystemV7CanonicalJson -Value $blockMap)
$draftPath = Join-Path $bundleRoot 'DRAFT_BLOCKS.md'
$draftText = @('SCHEMA: K3_ASSEMBLED_DRAFT_V2','<!-- K3_BLOCK_MAP_BEGIN -->','```json',(ConvertTo-SystemV7CanonicalJson -Value $blockMap).Trim(),'```','<!-- K3_BLOCK_MAP_END -->','## NARRACJA ROBOCZA','Syntetyczna narracja checkpointu.') -join "`n"
Write-Utf8Lf -Path $draftPath -Text $draftText
$cleanDraftPath = Join-Path $bundleRoot "clean-narration-$draftSha.md"
Write-Utf8Lf -Path $cleanDraftPath -Text "Syntetyczna narracja checkpointu.`n"
$architecturePath = Join-Path $bundleRoot 'ARCHITECTURE.md'
$architectureText = @('<!-- NARRATIVE_V2_JSON_BEGIN -->','```json',(ConvertTo-SystemV7CanonicalJson -Value $architecture).Trim(),'```','<!-- NARRATIVE_V2_JSON_END -->') -join "`n"
Write-Utf8Lf -Path $architecturePath -Text $architectureText
$projectionPath = Join-Path $bundleRoot 'NQ_NR_VC.json'
Write-Utf8Lf -Path $projectionPath -Text (ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='K4_NQ_NR_VC_PROJECTION_V1';questions=$questions;reveals=$reveals;viewer_contacts=$viewerContacts}))
$voiceExemplarsPath = Join-Path $bundleRoot 'VOICE_EXEMPLARS.md'
Write-Utf8Lf -Path $voiceExemplarsPath -Text "VOICE_EXEMPLARS: BRAK`n"
$voiceExemplarsSha = Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7LfText -Text (Get-Content -LiteralPath $voiceExemplarsPath -Raw -Encoding UTF8))
$semanticPath = Join-Path $bundleRoot 'SEMANTIC_PREFLIGHT.json'
Write-Utf8Lf -Path $semanticPath -Text (ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{
    schema='NARRATIVE_SEMANTIC_PREFLIGHT_V1';draft_sha256=$draftSha;architecture_revision='';voice_exemplars_sha256=$voiceExemplarsSha;findings=@()
}))
$locatorPath = Join-Path $bundleRoot 'SOURCE_LOCATORS.json'
$locatorCards = foreach($i in 1..5){[ordered]@{p_id=('#P-{0:D3}' -f $i);source_id=('SRC-{0:D3}' -f $i);locator=("plik source-$i.txt, linia $i");qa_k1='GOTOWA'}}
Write-Utf8Lf -Path $locatorPath -Text (ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='SOURCE_LOCATORS_V1';evidence_sha256=('C'*64);cards=@($locatorCards)}))

$editorBundle = [pscustomobject]@{entries=@((New-Entry 'CLEAN_DRAFT' $cleanDraftPath),(New-Entry 'BLOCK_MAP' $blockMapPath),(New-Entry 'ARCHITECTURE' $architecturePath),(New-Entry 'NQ_NR_VC' $projectionPath),(New-Entry 'SEMANTIC_PREFLIGHT' $semanticPath),(New-Entry 'VOICE_EXEMPLARS' $voiceExemplarsPath))}
$verifyBundle = [pscustomobject]@{entries=@((New-Entry 'DRAFT_BLOCKS' $draftPath),(New-Entry 'SOURCE_LOCATORS' $locatorPath))}
$editorInventory = Get-SystemV7K4BundleInventoryState -ProjectPath $project -Lens EDITOR -BundleData $editorBundle
$verifyInventory = Get-SystemV7K4BundleInventoryState -ProjectPath $project -Lens VERIFY -BundleData $verifyBundle
if(-not $editorInventory.Valid -or -not $verifyInventory.Valid){throw "BASE_INVENTORY_INVALID editor=$($editorInventory.Errors -join ',') verify=$($verifyInventory.Errors -join ',')"}

function Add-StatusRows($Rows) {
    @($Rows | ForEach-Object {
        $copy=[ordered]@{}
        if($_ -is [Collections.IDictionary]){foreach($key in $_.Keys){$copy[[string]$key]=$_[$key]}}
        else{foreach($property in $_.PSObject.Properties){$copy[$property.Name]=$property.Value}}
        $copy.status='PASS';[pscustomobject]$copy
    })
}

function Get-MachineRows([string]$Prefix, $Rows) {
    $lines=[Collections.Generic.List[string]]::new()
    $materialized=@($Rows|Where-Object{$null -ne $_})
    if($materialized.Count -eq 0){$lines.Add("${Prefix}: BRAK")}else{foreach($row in Add-StatusRows $materialized){$lines.Add("${Prefix}: $($row|ConvertTo-Json -Compress -Depth 32)")}}
    $lines -join "`n"
}

function Get-MachineBody([string]$Prefix, $Rows, [string]$Analysis) {
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add((Get-MachineRows $Prefix $Rows))
    $lines.Add("ANALYSIS: $Analysis")
    $lines -join "`n"
}

function New-VerifyText($Coverage,$Locators,[switch]$GenericCoverage,[switch]$GenericLocators) {
    $coverageBody=if($GenericCoverage){'ANALYSIS: Ogólna analiza twierdzi, że wszystkie bloki oraz karty zostały sprawdzone bez wskazania pełnej mapy.'}else{Get-MachineBody 'COVERAGE_JSON' $Coverage 'Każdy blok został porównany z dokładnym zestawem kart, bez pomijania i bez dopisywania obcych identyfikatorów.'}
    $locatorBody=if($GenericLocators){'ANALYSIS: Ogólna analiza twierdzi, że lokalizatory sprawdzono poprawnie, ale nie przedstawia zamkniętej listy kart.'}else{Get-MachineBody 'LOCATOR_JSON' $Locators 'Każda użyta karta ma jawnie sprawdzone źródło oraz odtwarzalny lokalizator prowadzący do konkretnego fragmentu.'}
@"
SCHEMA: K4_VERIFY_OUTPUT_V1
LENS: VERIFY
DRAFT_SHA256: $draftSha
VERDICT: PASS
CRITICAL_COUNT: 0
MAJOR_COUNT: 0
MINOR_COUNT: 0
REVIEW_ALERT_COUNT: 0
## CLAIM_COVERAGE
$coverageBody
## SOURCE_LOCATORS_CHECKED
$locatorBody
## ATTRIBUTION_UNCERTAINTY
Atrybucje i poziom pewności pozostają zgodne z przekazanymi kartami oraz językiem zastosowanym w narracji.
## CONTRADICTIONS
Porównanie wszystkich przekazanych twierdzeń nie ujawniło sprzeczności zmieniających znaczenie materiału.
## FINDINGS
BRAK
"@
}

function New-EditorText($Acts,$Nq,$Nr,$Vc,$Required,[string]$GenericSection='') {
    $qr=if($GenericSection -ceq 'QUESTION_REVEAL_LOGIC'){'ANALYSIS: Ogólna analiza deklaruje poprawność pytań i revealów, lecz pomija dokładne rekordy wymagane przez kontrakt.'}else{(Get-MachineRows 'NQ_JSON' $Nq)+"`n"+(Get-MachineRows 'NR_JSON' $Nr)+"`nANALYSIS: Pytania i reveale mają jawne węzły, dowody oraz bloki realizacji, dlatego ich pełny cykl można odtworzyć."}
    $actBody=if($GenericSection -ceq 'TWO_AXES_AND_STATE_CHANGE'){'ANALYSIS: Ogólna analiza deklaruje zmianę stanu w aktach, ale nie przedstawia wymaganych rekordów powiązań.'}else{Get-MachineBody 'ACT_JSON' $Acts 'Każdy akt wiąże bloki, sceny oraz węzeł zmiany stanu w jednej sprawdzalnej projekcji.'}
    $requiredBody=if($GenericSection -ceq 'EXPOSITION_TRANSITIONS'){'ANALYSIS: Ogólna analiza deklaruje poprawne dowody wymagane, lecz nie przedstawia zamkniętej mapy scen i bloków.'}else{Get-MachineBody 'REQUIRED_JSON' $Required 'Każdy wymagany dowód ma funkcję, konieczność oraz blok realizacji w odpowiednim akcie.'}
    $vcBody=if($GenericSection -ceq 'VOICE_VIEWER_CONTACT'){'ANALYSIS: Ogólna analiza deklaruje poprawne kontakty z widzem, lecz pomija ich dokładną mapę do węzłów.'}else{(Get-MachineRows 'VC_JSON' $Vc)+"`n"+(Get-MachineRows 'PREFLIGHT_JSON' @($editorInventory.SemanticFindings))+"`nANALYSIS: Każdy kontakt i alert preflight sprawdzono względem funkcji, głosu oraz jawnie przypisanego bloku."}
@"
SCHEMA: K4_EDITOR_OUTPUT_V1
LENS: EDITOR
DRAFT_SHA256: $draftSha
VERDICT: PASS
CRITICAL_COUNT: 0
MAJOR_COUNT: 0
MINOR_COUNT: 0
REVIEW_ALERT_COUNT: 0
## HOOK_AND_PROMISE
Otwarcie jasno przedstawia stawkę, obietnicę oraz konkretny kierunek dalszej narracji dla widza.
## QUESTION_REVEAL_LOGIC
$qr
## TWO_AXES_AND_STATE_CHANGE
$actBody
## EXPOSITION_TRANSITIONS
$requiredBody
## VOICE_VIEWER_CONTACT
$vcBody
## FINALE
Finał rozwiązuje główne pytanie, wypłaca obietnicę i pozostawia wyraźny końcowy obraz dla widza.
## FINDINGS
BRAK
"@
}

$results=[Collections.Generic.List[object]]::new()
function Invoke-LensCase([string]$Name,[string]$Lens,[string]$Text,[object]$Bundle,[bool]$ExpectedValid,[string]$ExpectedError) {
    $path=Join-Path $outputRoot "$Name.md";Write-Utf8Lf -Path $path -Text $Text
    $state=Get-SystemV7K4LensOutputState -ProjectPath $project -Lens $Lens -OutputPath $path -ExpectedDraftSha256 $draftSha -BundleData $Bundle
    $found=if([string]::IsNullOrWhiteSpace($ExpectedError)){$true}else{@($state.Errors|Where-Object{$_ -like "$ExpectedError*"}).Count -gt 0}
    $results.Add([pscustomobject]@{Case=$Name;Layer='K4_OUTPUT';ActualValid=[bool]$state.Valid;ExpectedValid=$ExpectedValid;ExpectedError=$ExpectedError;ErrorFound=$found;Pass=([bool]$state.Valid -eq $ExpectedValid)-and$found;Errors=@($state.Errors)})
}

$coverage=@($verifyInventory.Coverage);$locators=@($verifyInventory.Locators)
Invoke-LensCase 'verify-positive' 'VERIFY' (New-VerifyText $coverage $locators) $verifyBundle $true ''

$x=@($coverage[0..($coverage.Count-2)]);Invoke-LensCase 'verify-coverage-missing' 'VERIFY' (New-VerifyText $x $locators) $verifyBundle $false 'K4_MACHINE_ROW_COUNT_MISMATCH: CLAIM_COVERAGE/COVERAGE_JSON'
$x=@($coverage)+@([pscustomobject]@{block_id='BLOCK-ACT-999-001';p_ids=@('#P-999')});Invoke-LensCase 'verify-coverage-extra' 'VERIFY' (New-VerifyText $x $locators) $verifyBundle $false 'K4_MACHINE_ROW_COUNT_MISMATCH: CLAIM_COVERAGE/COVERAGE_JSON'
$x=@($coverage)+@($coverage[0]);Invoke-LensCase 'verify-coverage-duplicate' 'VERIFY' (New-VerifyText $x $locators) $verifyBundle $false 'K4_MACHINE_ROW_COUNT_MISMATCH: CLAIM_COVERAGE/COVERAGE_JSON'
$x=Copy-Data $coverage;$tmp=$x[0].p_ids;$x[0].p_ids=$x[1].p_ids;$x[1].p_ids=$tmp;Invoke-LensCase 'verify-block-p-wrong-map' 'VERIFY' (New-VerifyText $x $locators) $verifyBundle $false 'K4_MACHINE_ROW_MAPPING_MISMATCH: CLAIM_COVERAGE/COVERAGE_JSON'
$x=Copy-Data $coverage;$x[2].p_ids=@('#P-003');Invoke-LensCase 'verify-p-missing-in-row' 'VERIFY' (New-VerifyText $x $locators) $verifyBundle $false 'K4_MACHINE_ROW_MAPPING_MISMATCH: CLAIM_COVERAGE/COVERAGE_JSON'
$x=Copy-Data $coverage;$x[0].p_ids=@('#P-001','#P-001');Invoke-LensCase 'verify-p-duplicate-in-row' 'VERIFY' (New-VerifyText $x $locators) $verifyBundle $false 'K4_MACHINE_ROW_MAPPING_MISMATCH: CLAIM_COVERAGE/COVERAGE_JSON'
$x=@($locators[0..($locators.Count-2)]);Invoke-LensCase 'verify-locator-missing' 'VERIFY' (New-VerifyText $coverage $x) $verifyBundle $false 'K4_MACHINE_ROW_COUNT_MISMATCH: SOURCE_LOCATORS_CHECKED/LOCATOR_JSON'
$x=@($locators)+@([pscustomobject]@{p_id='#P-999';source_id='SRC-999';locator='plik extra.txt, linia 1'});Invoke-LensCase 'verify-locator-extra' 'VERIFY' (New-VerifyText $coverage $x) $verifyBundle $false 'K4_MACHINE_ROW_COUNT_MISMATCH: SOURCE_LOCATORS_CHECKED/LOCATOR_JSON'
$x=@($locators)+@($locators[0]);Invoke-LensCase 'verify-locator-duplicate' 'VERIFY' (New-VerifyText $coverage $x) $verifyBundle $false 'K4_MACHINE_ROW_COUNT_MISMATCH: SOURCE_LOCATORS_CHECKED/LOCATOR_JSON'
$x=Copy-Data $locators;$tmp=$x[0].locator;$x[0].locator=$x[1].locator;$x[1].locator=$tmp;Invoke-LensCase 'verify-locator-wrong-map' 'VERIFY' (New-VerifyText $coverage $x) $verifyBundle $false 'K4_MACHINE_ROW_MAPPING_MISMATCH: SOURCE_LOCATORS_CHECKED/LOCATOR_JSON'
Invoke-LensCase 'verify-one-block-false-pass' 'VERIFY' (New-VerifyText @($coverage[0]) @($locators[0])) $verifyBundle $false 'K4_MACHINE_ROW_COUNT_MISMATCH'
Invoke-LensCase 'verify-generic-text-bypass' 'VERIFY' (New-VerifyText $coverage $locators -GenericCoverage) $verifyBundle $false 'K4_MACHINE_ROW_COUNT_MISMATCH: CLAIM_COVERAGE/COVERAGE_JSON'

$a=@($editorInventory.Acts);$nq=@($editorInventory.Questions);$nr=@($editorInventory.Reveals);$vc=@($editorInventory.ViewerContacts);$req=@($editorInventory.Required)
Invoke-LensCase 'editor-positive' 'EDITOR' (New-EditorText $a $nq $nr $vc $req) $editorBundle $true ''

$domains=@(
    [pscustomobject]@{Name='act';Rows=$a;ErrorSection='TWO_AXES_AND_STATE_CHANGE';Prefix='ACT_JSON';IdField='act_id';MapField='block_ids'},
    [pscustomobject]@{Name='nq';Rows=$nq;ErrorSection='QUESTION_REVEAL_LOGIC';Prefix='NQ_JSON';IdField='nq_id';MapField='block_ids'},
    [pscustomobject]@{Name='nr';Rows=$nr;ErrorSection='QUESTION_REVEAL_LOGIC';Prefix='NR_JSON';IdField='nr_id';MapField='block_ids'},
    [pscustomobject]@{Name='vc';Rows=$vc;ErrorSection='VOICE_VIEWER_CONTACT';Prefix='VC_JSON';IdField='vc_id';MapField='block_ids'},
    [pscustomobject]@{Name='required';Rows=$req;ErrorSection='EXPOSITION_TRANSITIONS';Prefix='REQUIRED_JSON';IdField='sw_id';MapField='block_ids'}
)
foreach($domain in $domains){
    $sets=@{Acts=$a;Nq=$nq;Nr=$nr;Vc=$vc;Required=$req}
    $rows=@($domain.Rows)
    $missing=if($rows.Count -gt 1){@($rows[0..($rows.Count-2)])}else{@()};$sets[$(@{act='Acts';nq='Nq';nr='Nr';vc='Vc';required='Required'}[$domain.Name])]=$missing
    $missingError=if($rows.Count -gt 1){"K4_MACHINE_ROW_COUNT_MISMATCH: $($domain.ErrorSection)/$($domain.Prefix)"}else{"K4_MACHINE_BRAK_WITH_EXPECTED_ROWS: $($domain.ErrorSection)/$($domain.Prefix)"}
    Invoke-LensCase "editor-$($domain.Name)-missing" 'EDITOR' (New-EditorText $sets.Acts $sets.Nq $sets.Nr $sets.Vc $sets.Required) $editorBundle $false $missingError
    $sets=@{Acts=$a;Nq=$nq;Nr=$nr;Vc=$vc;Required=$req};$extra=@($rows)+@($rows[0]);$sets[$(@{act='Acts';nq='Nq';nr='Nr';vc='Vc';required='Required'}[$domain.Name])]=$extra
    Invoke-LensCase "editor-$($domain.Name)-duplicate" 'EDITOR' (New-EditorText $sets.Acts $sets.Nq $sets.Nr $sets.Vc $sets.Required) $editorBundle $false "K4_MACHINE_ROW_COUNT_MISMATCH: $($domain.ErrorSection)/$($domain.Prefix)"
    $sets=@{Acts=$a;Nq=$nq;Nr=$nr;Vc=$vc;Required=$req};$foreign=Copy-Data $rows[0];$foreign.($domain.IdField)=if($domain.IdField -ceq 'act_id'){'ACT-999'}elseif($domain.IdField -ceq 'nq_id'){'NQ-999'}elseif($domain.IdField -ceq 'nr_id'){'NR-999'}elseif($domain.IdField -ceq 'vc_id'){'VC-999'}else{'SW-999'};$extra=@($rows)+@($foreign);$sets[$(@{act='Acts';nq='Nq';nr='Nr';vc='Vc';required='Required'}[$domain.Name])]=$extra
    Invoke-LensCase "editor-$($domain.Name)-extra" 'EDITOR' (New-EditorText $sets.Acts $sets.Nq $sets.Nr $sets.Vc $sets.Required) $editorBundle $false "K4_MACHINE_ROW_COUNT_MISMATCH: $($domain.ErrorSection)/$($domain.Prefix)"
    $sets=@{Acts=$a;Nq=$nq;Nr=$nr;Vc=$vc;Required=$req};$wrong=Copy-Data $rows;if($wrong.Count -gt 1){$tmp=$wrong[0].($domain.MapField);$wrong[0].($domain.MapField)=$wrong[1].($domain.MapField);$wrong[1].($domain.MapField)=$tmp}else{$wrong[0].($domain.MapField)=@('BLOCK-ACT-999-001')};$sets[$(@{act='Acts';nq='Nq';nr='Nr';vc='Vc';required='Required'}[$domain.Name])]=$wrong
    Invoke-LensCase "editor-$($domain.Name)-wrong-map" 'EDITOR' (New-EditorText $sets.Acts $sets.Nq $sets.Nr $sets.Vc $sets.Required) $editorBundle $false "K4_MACHINE_ROW_MAPPING_MISMATCH: $($domain.ErrorSection)/$($domain.Prefix)"
}
foreach($section in @('QUESTION_REVEAL_LOGIC','TWO_AXES_AND_STATE_CHANGE','EXPOSITION_TRANSITIONS','VOICE_VIEWER_CONTACT')){Invoke-LensCase "editor-generic-$($section.ToLowerInvariant())" 'EDITOR' (New-EditorText $a $nq $nr $vc $req $section) $editorBundle $false 'K4_MACHINE_ROW_COUNT_MISMATCH'}

function New-BasePacket {
    $registry=[ordered]@{
        schema='NARRATIVE_ACTION_REGISTRY_V1';act_id='ACT-001';questions=@([ordered]@{nq_id='NQ-001';question='Co się wydarzyło';opened_at='SW-001';why_care='Napędza akt';expected_form='ANSWER';payoff_node='SW-002';status='CLOSED'});reveals=@([ordered]@{nr_id='NR-001';reveal='Kluczowy fakt';evidence_p_ids=@('#P-002','#P-003');earliest_legal_node='SW-002';target_node='SW-002';setup_required='Zbuduj kontekst';do_not_reveal_before='SW-002';consequence='Zmienia model';uncertainty_form='Zachowaj niepewność'});viewer_contacts=@(
            [ordered]@{vc_id='VC-001';node='SW-001';function='ORIENT';level='MICRO';purpose='Orientuje widza';risk='Nie zdradza finału';author_text='BRAK';approval='NOT_REQUIRED';approval_receipt_relative='BRAK';approval_receipt_sha256='BRAK'},
            [ordered]@{vc_id='VC-002';node='SW-002';function='RECALL';level='STRUCTURAL';purpose='Przypomina obietnicę';risk='Nie powtarza ekspozycji';author_text='BRAK';approval='NOT_REQUIRED';approval_receipt_relative='BRAK';approval_receipt_sha256='BRAK'}
        )
    }
    $packet=[ordered]@{
        act_id='ACT-001';complexity_flag='COMPLEX';entry_knowledge_state='VIEW-0';exit_knowledge_state='VIEW-2';scene_weave_ids=@('SW-001','SW-002');required_p=@('#P-001','#P-002','#P-003');supporting_p=@();open_nq_ids=@();nq_actions=@('OPEN:NQ-001','PAY:NQ-001');nr_actions=@('SETUP:NR-001','REVEAL:NR-001');vc_ids=@('VC-001','VC-002');narrative_action_registry=$registry;narrative_action_registry_sha256=(Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $registry));scene_contracts=@(
            [ordered]@{sw_id='SW-001';scene_or_unit='Otwarcie';function='Otwórz pytanie';entry_knowledge_state='VIEW-0';exit_knowledge_state='VIEW-1';emotional_pressure='LOW';required_p=@('#P-001');supporting_p=@();nq_action='OPEN:NQ-001';nr_action='SETUP:NR-001';nr_evidence_p=@();vc_ids=@('VC-001');local_stake='Widz musi rozumieć stawkę';bridge_out='Przejdź do ujawnienia';completion_criteria='Pytanie otwarte'},
            [ordered]@{sw_id='SW-002';scene_or_unit='Ujawnienie';function='Wypłać pytanie';entry_knowledge_state='VIEW-1';exit_knowledge_state='VIEW-2';emotional_pressure='HIGH';required_p=@('#P-002','#P-003');supporting_p=@();nq_action='PAY:NQ-001';nr_action='REVEAL:NR-001';nr_evidence_p=@('#P-002','#P-003');vc_ids=@('VC-002');local_stake='Reveal zmienia model';bridge_out='Domknij akt';completion_criteria='Reveal udowodniony'}
        )
    }
    Copy-Data $packet
}
function New-BaseBeat {
    Copy-Data ([ordered]@{schema='K3_BEAT_SHEET_V1';act_id='ACT-001';packet_status='BEAT_SHEET_READY';generate_run_id='GENERATE.ACT-001.0001';beats=@(
        [ordered]@{beat_id='BEAT-001';sw_id='SW-001';function='Otwarcie pytania';source_p_ids=@('#P-001');state_before='VIEW-0';state_after='VIEW-1';nq_nr_vc_ids=@('OPEN:NQ-001','SETUP:NR-001','VC-001')},
        [ordered]@{beat_id='BEAT-002';sw_id='SW-002';function='Ujawnienie i wypłata';source_p_ids=@('#P-002','#P-003');state_before='VIEW-1';state_after='VIEW-2';nq_nr_vc_ids=@('PAY:NQ-001','REVEAL:NR-001','VC-002')}
    )})
}
function Add-StateCase([string]$Name,[string]$Layer,$State,[bool]$ExpectedValid,[string]$ExpectedError){$found=if(!$ExpectedError){$true}else{@($State.Errors|Where-Object{$_ -like "$ExpectedError*"}).Count -gt 0};$results.Add([pscustomobject]@{Case=$Name;Layer=$Layer;ActualValid=[bool]$State.Valid;ExpectedValid=$ExpectedValid;ExpectedError=$ExpectedError;ErrorFound=$found;Pass=([bool]$State.Valid-eq$ExpectedValid)-and$found;Errors=@($State.Errors)})}

$semanticBadBindingPath=Join-Path $bundleRoot 'SEMANTIC_PREFLIGHT-BAD-BINDING.json'
Write-Utf8Lf -Path $semanticBadBindingPath -Text (ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='NARRATIVE_SEMANTIC_PREFLIGHT_V1';draft_sha256=('E'*64);architecture_revision='';voice_exemplars_sha256=('F'*64);findings=@()}))
$semanticBadBindingBundle=[pscustomobject]@{entries=@((New-Entry 'CLEAN_DRAFT' $cleanDraftPath),(New-Entry 'BLOCK_MAP' $blockMapPath),(New-Entry 'ARCHITECTURE' $architecturePath),(New-Entry 'NQ_NR_VC' $projectionPath),(New-Entry 'SEMANTIC_PREFLIGHT' $semanticBadBindingPath),(New-Entry 'VOICE_EXEMPLARS' $voiceExemplarsPath))}
Add-StateCase 'inventory-semantic-binding-tamper' 'K4_INVENTORY' (Get-SystemV7K4BundleInventoryState -ProjectPath $project -Lens EDITOR -BundleData $semanticBadBindingBundle) $false 'K4_INVENTORY_SEMANTIC_PREFLIGHT_SCHEMA_OR_BINDING_INVALID'

$semanticUnknownFindingPath=Join-Path $bundleRoot 'SEMANTIC_PREFLIGHT-UNKNOWN-FINDING.json'
Write-Utf8Lf -Path $semanticUnknownFindingPath -Text (ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='NARRATIVE_SEMANTIC_PREFLIGHT_V1';draft_sha256=$draftSha;architecture_revision='';voice_exemplars_sha256=$voiceExemplarsSha;findings=@([ordered]@{finding_id='SP-001';class='REVIEW_ALERT';rule_id='UNKNOWN_RULE';act_id='ACT-999';block_id='BLOCK-ACT-999-999';evidence='Nieznany wpis nie może wejść do rejestru.'})}))
$semanticUnknownFindingBundle=[pscustomobject]@{entries=@((New-Entry 'CLEAN_DRAFT' $cleanDraftPath),(New-Entry 'BLOCK_MAP' $blockMapPath),(New-Entry 'ARCHITECTURE' $architecturePath),(New-Entry 'NQ_NR_VC' $projectionPath),(New-Entry 'SEMANTIC_PREFLIGHT' $semanticUnknownFindingPath),(New-Entry 'VOICE_EXEMPLARS' $voiceExemplarsPath))}
Add-StateCase 'inventory-semantic-unknown-rule-and-owner' 'K4_INVENTORY' (Get-SystemV7K4BundleInventoryState -ProjectPath $project -Lens EDITOR -BundleData $semanticUnknownFindingBundle) $false 'K4_INVENTORY_SEMANTIC_FINDING_INVALID: SP-001'

$semanticWrongCasePath=Join-Path $bundleRoot 'SEMANTIC_PREFLIGHT-WRONG-CASE-RULE.json'
Write-Utf8Lf -Path $semanticWrongCasePath -Text (ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='NARRATIVE_SEMANTIC_PREFLIGHT_V1';draft_sha256=$draftSha;architecture_revision='';voice_exemplars_sha256=$voiceExemplarsSha;findings=@([ordered]@{finding_id='SP-001';class='REVIEW_ALERT';rule_id='unplanned_direct_viewer_contact';act_id='ACT-001';block_id='BLOCK-ACT-001-001';evidence='Ty widzisz ten problem bez dodatkowego komentarza.'})}))
$semanticWrongCaseBundle=[pscustomobject]@{entries=@((New-Entry 'CLEAN_DRAFT' $cleanDraftPath),(New-Entry 'BLOCK_MAP' $blockMapPath),(New-Entry 'ARCHITECTURE' $architecturePath),(New-Entry 'NQ_NR_VC' $projectionPath),(New-Entry 'SEMANTIC_PREFLIGHT' $semanticWrongCasePath),(New-Entry 'VOICE_EXEMPLARS' $voiceExemplarsPath))}
Add-StateCase 'inventory-semantic-rule-case-bypass' 'K4_INVENTORY' (Get-SystemV7K4BundleInventoryState -ProjectPath $project -Lens EDITOR -BundleData $semanticWrongCaseBundle) $false 'K4_INVENTORY_SEMANTIC_FINDING_INVALID: SP-001'

$semanticWrongOwnerPath=Join-Path $bundleRoot 'SEMANTIC_PREFLIGHT-WRONG-OWNER.json'
Write-Utf8Lf -Path $semanticWrongOwnerPath -Text (ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='NARRATIVE_SEMANTIC_PREFLIGHT_V1';draft_sha256=$draftSha;architecture_revision='';voice_exemplars_sha256=$voiceExemplarsSha;findings=@([ordered]@{finding_id='SP-001';class='REVIEW_ALERT';rule_id='UNPLANNED_DIRECT_VIEWER_CONTACT';act_id='ACT-002';block_id='BLOCK-ACT-001-001';evidence='Ty widzisz ten problem bez dodatkowego komentarza.'})}))
$semanticWrongOwnerBundle=[pscustomobject]@{entries=@((New-Entry 'CLEAN_DRAFT' $cleanDraftPath),(New-Entry 'BLOCK_MAP' $blockMapPath),(New-Entry 'ARCHITECTURE' $architecturePath),(New-Entry 'NQ_NR_VC' $projectionPath),(New-Entry 'SEMANTIC_PREFLIGHT' $semanticWrongOwnerPath),(New-Entry 'VOICE_EXEMPLARS' $voiceExemplarsPath))}
Add-StateCase 'inventory-semantic-act-block-owner-mismatch' 'K4_INVENTORY' (Get-SystemV7K4BundleInventoryState -ProjectPath $project -Lens EDITOR -BundleData $semanticWrongOwnerBundle) $false 'K4_INVENTORY_SEMANTIC_FINDING_INVALID: SP-001'

$semanticBadEvidencePath=Join-Path $bundleRoot 'SEMANTIC_PREFLIGHT-BAD-DIRECT-EVIDENCE.json'
Write-Utf8Lf -Path $semanticBadEvidencePath -Text (ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='NARRATIVE_SEMANTIC_PREFLIGHT_V1';draft_sha256=$draftSha;architecture_revision='';voice_exemplars_sha256=$voiceExemplarsSha;findings=@([ordered]@{finding_id='SP-001';class='REVIEW_ALERT';rule_id='UNPLANNED_DIRECT_VIEWER_CONTACT';act_id='ACT-001';block_id='BLOCK-ACT-001-001';evidence='Neutralne zdanie bez bezpośredniego kontaktu.'})}))
$semanticBadEvidenceBundle=[pscustomobject]@{entries=@((New-Entry 'CLEAN_DRAFT' $cleanDraftPath),(New-Entry 'BLOCK_MAP' $blockMapPath),(New-Entry 'ARCHITECTURE' $architecturePath),(New-Entry 'NQ_NR_VC' $projectionPath),(New-Entry 'SEMANTIC_PREFLIGHT' $semanticBadEvidencePath),(New-Entry 'VOICE_EXEMPLARS' $voiceExemplarsPath))}
Add-StateCase 'inventory-semantic-direct-contact-evidence-shape' 'K4_INVENTORY' (Get-SystemV7K4BundleInventoryState -ProjectPath $project -Lens EDITOR -BundleData $semanticBadEvidenceBundle) $false 'K4_INVENTORY_SEMANTIC_FINDING_INVALID: SP-001'

$collisionArchitecture=Copy-Data $architecture
$collisionArchitecture.scene_weave[1].required_evidence=@([pscustomobject]@{p_id='#P-001';function='Ten sam dowód ma zostać zrealizowany ponownie';necessity='Musi wystąpić w SW-002'})
$collisionArchitecturePath=Join-Path $bundleRoot 'ARCHITECTURE-REQUIRED-COLLISION.md'
Write-Utf8Lf -Path $collisionArchitecturePath -Text (@('<!-- NARRATIVE_V2_JSON_BEGIN -->','```json',(ConvertTo-SystemV7CanonicalJson -Value $collisionArchitecture).Trim(),'```','<!-- NARRATIVE_V2_JSON_END -->') -join "`n")
$collisionProjectionPath=Join-Path $bundleRoot 'NQ_NR_VC-REQUIRED-COLLISION.json'
Write-Utf8Lf -Path $collisionProjectionPath -Text (ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='K4_NQ_NR_VC_PROJECTION_V1';questions=@($collisionArchitecture.questions);reveals=@($collisionArchitecture.reveals);viewer_contacts=@($collisionArchitecture.viewer_contacts)}))
$collisionBundle=[pscustomobject]@{entries=@((New-Entry 'CLEAN_DRAFT' $cleanDraftPath),(New-Entry 'BLOCK_MAP' $blockMapPath),(New-Entry 'ARCHITECTURE' $collisionArchitecturePath),(New-Entry 'NQ_NR_VC' $collisionProjectionPath),(New-Entry 'SEMANTIC_PREFLIGHT' $semanticPath),(New-Entry 'VOICE_EXEMPLARS' $voiceExemplarsPath))}
$collisionInventory=Get-SystemV7K4BundleInventoryState -ProjectPath $project -Lens EDITOR -BundleData $collisionBundle
Add-StateCase 'inventory-required-same-p-wrong-sw' 'K4_INVENTORY' $collisionInventory $false 'K4_INVENTORY_REQUIRED_BLOCK_MAPPING_EMPTY: SW-002/#P-001'

$complexBlockMap=Copy-Data $blockMap
$complexBlockMap.acts[0].blocks[0].trace_refs=@('BEAT-001')
$complexBlockMap.acts[0].blocks[1].trace_refs=@('BEAT-002')
$complexBlockMapPath=Join-Path $bundleRoot 'BLOCK_MAP-COMPLEX.json'
Write-Utf8Lf -Path $complexBlockMapPath -Text (ConvertTo-SystemV7CanonicalJson -Value $complexBlockMap)
$complexBundle=[pscustomobject]@{entries=@((New-Entry 'CLEAN_DRAFT' $cleanDraftPath),(New-Entry 'BLOCK_MAP' $complexBlockMapPath),(New-Entry 'ARCHITECTURE' $architecturePath),(New-Entry 'NQ_NR_VC' $projectionPath),(New-Entry 'SEMANTIC_PREFLIGHT' $semanticPath),(New-Entry 'VOICE_EXEMPLARS' $voiceExemplarsPath))}
$complexInventory=Get-SystemV7K4BundleInventoryState -ProjectPath $project -Lens EDITOR -BundleData $complexBundle
Add-StateCase 'inventory-complex-beat-explicit-sw-positive' 'K4_INVENTORY' $complexInventory $true ''

$complexCollisionBundle=[pscustomobject]@{entries=@((New-Entry 'CLEAN_DRAFT' $cleanDraftPath),(New-Entry 'BLOCK_MAP' $complexBlockMapPath),(New-Entry 'ARCHITECTURE' $collisionArchitecturePath),(New-Entry 'NQ_NR_VC' $collisionProjectionPath),(New-Entry 'SEMANTIC_PREFLIGHT' $semanticPath),(New-Entry 'VOICE_EXEMPLARS' $voiceExemplarsPath))}
$complexCollisionInventory=Get-SystemV7K4BundleInventoryState -ProjectPath $project -Lens EDITOR -BundleData $complexCollisionBundle
Add-StateCase 'inventory-complex-beat-same-p-wrong-sw' 'K4_INVENTORY' $complexCollisionInventory $false 'K4_INVENTORY_REQUIRED_BLOCK_MAPPING_EMPTY: SW-002/#P-001'

$packet=New-BasePacket;$packetState=Get-SystemV7PacketSceneContractState -Packet $packet;Add-StateCase 'packet-positive' 'PACKET' $packetState $true ''
$mut=Copy-Data $packet;$mut.scene_contracts[0].vc_ids=@('VC-002');$mut.scene_contracts[1].vc_ids=@('VC-001');Add-StateCase 'packet-vc-wrong-owner' 'PACKET' (Get-SystemV7PacketSceneContractState -Packet $mut) $false 'PACKET_SCENE_CONTRACT_VC_MAP_MISMATCH'
$mut=Copy-Data $packet;$mut.scene_contracts[1].nr_evidence_p=@('#P-002');Add-StateCase 'packet-reveal-evidence-missing' 'PACKET' (Get-SystemV7PacketSceneContractState -Packet $mut) $false 'PACKET_SCENE_CONTRACT_REVEAL_EVIDENCE_MISMATCH'
$mut=Copy-Data $packet;$mut.scene_contracts[0].exit_knowledge_state='VIEW-X';Add-StateCase 'packet-sw-adjacency-broken' 'PACKET' (Get-SystemV7PacketSceneContractState -Packet $mut) $false 'PACKET_SCENE_CONTRACT_STATE_CHAIN_BROKEN'

$beat=New-BaseBeat;Add-StateCase 'beat-positive' 'BEAT' (Get-SystemV7BeatSheetSemanticState -Packet $packet -BeatSheet $beat -ActId 'ACT-001' -ExpectedGenerateRunId 'GENERATE.ACT-001.0001') $true ''
$mutBeat=Copy-Data $beat;$mutBeat.beats[1].source_p_ids=@('#P-002');Add-StateCase 'beat-reveal-evidence-not-cooccurrent' 'BEAT' (Get-SystemV7BeatSheetSemanticState -Packet $packet -BeatSheet $mutBeat -ActId 'ACT-001' -ExpectedGenerateRunId 'GENERATE.ACT-001.0001') $false 'BEAT_REVEAL_EVIDENCE_NOT_COOCCURRENT'
$mutBeat=Copy-Data $beat;$mutBeat.beats[0].sw_id='SW-002';$mutBeat.beats[1].sw_id='SW-001';Add-StateCase 'beat-sw-order-wrong' 'BEAT' (Get-SystemV7BeatSheetSemanticState -Packet $packet -BeatSheet $mutBeat -ActId 'ACT-001' -ExpectedGenerateRunId 'GENERATE.ACT-001.0001') $false 'BEAT_SW_ORDER_REGRESSION'

$blocks=@(
    [pscustomobject][ordered]@{trace_refs=@('BEAT-001');source_p_ids=@('#P-001');narrative_refs=@('OPEN:NQ-001','SETUP:NR-001','VC-001');prose='Blok otwiera pytanie i orientuje widza w sytuacji.'},
    [pscustomobject][ordered]@{trace_refs=@('BEAT-002');source_p_ids=@('#P-002','#P-003');narrative_refs=@('PAY:NQ-001','REVEAL:NR-001','VC-002');prose='Blok ujawnia fakt i wypłaca pytanie na podstawie obu kart.'}
)
Add-StateCase 'trace-positive' 'TRACE' (Get-SystemV7ActSubmissionTraceState -Packet $packet -Blocks $blocks -BeatSheet $beat) $true ''
$mutBlocks=Copy-Data $blocks;$mutBlocks[1].source_p_ids=@('#P-002');Add-StateCase 'trace-reveal-evidence-not-cooccurrent' 'TRACE' (Get-SystemV7ActSubmissionTraceState -Packet $packet -Blocks $mutBlocks -BeatSheet $beat) $false 'ACT_TRACE_REVEAL_EVIDENCE_NOT_COOCCURRENT'
$mutBlocks=Copy-Data $blocks;$mutBlocks[0].trace_refs=@('BEAT-002');$mutBlocks[1].trace_refs=@('BEAT-001');Add-StateCase 'trace-sw-beat-adjacency-wrong' 'TRACE' (Get-SystemV7ActSubmissionTraceState -Packet $packet -Blocks $mutBlocks -BeatSheet $beat) $false 'ACT_TRACE_ORDER_REGRESSION'

$failed=@($results|Where-Object{-not $_.Pass})
[pscustomobject]@{FixturePath=$project;NarrativeReceiptsSha256=(Get-FileHash -LiteralPath (Join-Path $tools 'Narrative-Receipts.ps1') -Algorithm SHA256).Hash;NarrativeV2Sha256=(Get-FileHash -LiteralPath (Join-Path $tools 'Narrative-V2.ps1') -Algorithm SHA256).Hash;Total=$results.Count;Passed=$results.Count-$failed.Count;Failed=$failed.Count;FailedCases=@($failed.Case);Cases=@($results)}
if($failed.Count -gt 0){throw 'CHECKPOINT1_MATRIX_FAILED'}
