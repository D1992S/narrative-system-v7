param(
    [Parameter(Mandatory)][string]$SystemRoot,
    [Parameter(Mandatory)][string]$FixtureRoot,
    [Parameter(Mandatory)][string]$VoiceProfilePath
)
$ErrorActionPreference='Stop'

$systemRoot=[IO.Path]::GetFullPath($SystemRoot)
$fixtureRoot=[IO.Path]::GetFullPath($FixtureRoot)
$tools=Join-Path $systemRoot 'tools'
$sourceFixture=Join-Path $systemRoot '_SYSTEM\NARRATIVE\TEST-FIXTURES'
. (Join-Path $tools 'Project-Origin.ps1')
. (Join-Path $tools 'Narrative-V2.ps1')
. (Join-Path $tools 'Narrative-Receipts.ps1')
. (Join-Path $tools 'Integrity-Receipts.ps1')

function Write-Utf8Lf([string]$Path,[string]$Text){
    $value=(ConvertTo-SystemV7LfText -Text $Text)
    if(-not $value.EndsWith("`n")){$value+="`n"}
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))|Out-Null
    [IO.File]::WriteAllText($Path,$value,[Text.UTF8Encoding]::new($false))
}
function Set-Meta([string]$Project,[hashtable]$Values){
    $path=Join-Path $Project 'meta.md';$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
    foreach($key in $Values.Keys){$text=Set-SystemV7NarrativeMetaField -Text $text -Name $key -Value ([string]$Values[$key])}
    Write-SystemV7NarrativeAtomicText -Path $path -Text $text|Out-Null
}
function Get-Meta([string]$Project,[string]$Name){
    Get-SystemV7NarrativeMetaField -Text (Get-Content -LiteralPath (Join-Path $Project 'meta.md') -Raw -Encoding UTF8) -Name $Name
}
function Get-Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Copy-JsonObject([object]$Value){
    (ConvertTo-SystemV7CanonicalJson -Value $Value)|ConvertFrom-Json -DateKind String -Depth 64
}
function Write-Architecture([string]$Path,[object]$Architecture){
    $text=@('STATUS: GOTOWA','<!-- NARRATIVE_V2_JSON_BEGIN -->','```json',(ConvertTo-SystemV7CanonicalJson -Value $Architecture).Trim(),'```','<!-- NARRATIVE_V2_JSON_END -->') -join "`n"
    Write-Utf8Lf -Path $Path -Text $text
}

[IO.Directory]::CreateDirectory($fixtureRoot)|Out-Null

# ---------------------------------------------------------------------------
# Cache-domain regression: the ACT-001 packet must depend only on the shared
# Story Spine, ACT-001 projection, ACT-001 selected evidence and stable prefix.
# ---------------------------------------------------------------------------
$cacheRoot=Join-Path $fixtureRoot 'cache-domain';[IO.Directory]::CreateDirectory($cacheRoot)|Out-Null
$cacheProject=Join-Path $cacheRoot 'PROJECT-CACHE-DOMAIN'
& (Join-Path $tools 'New-Project.ps1') -ProjectName 'PROJECT-CACHE-DOMAIN' -DestinationRoot $cacheRoot -NarrativeV2Pilot|Out-Null
& (Join-Path $tools 'Set-VoiceProfileForProject.ps1') -ProjectPath $cacheProject -ProfilePath $VoiceProfilePath -ApprovalNote 'Jawny wybór profilu w regresji domeny unieważniania.' -DawidApproved|Out-Null

$sourceText=Get-Content -LiteralPath (Join-Path $sourceFixture 'complex-architecture.md') -Raw -Encoding UTF8
$match=[regex]::Match($sourceText,'(?s)<!--\s*NARRATIVE_V2_JSON_BEGIN\s*-->\s*```json\s*(?<json>.*?)\s*```\s*<!--\s*NARRATIVE_V2_JSON_END\s*-->')
if(-not $match.Success){throw 'INVALIDATION_SOURCE_ARCHITECTURE_JSON_MISSING'}
$architecture=$match.Groups['json'].Value|ConvertFrom-Json -DateKind String -Depth 64
$architecture.architecture_revision='CACHE-DOMAIN-V1'
$architecture.questions=[object[]]@();$architecture.reveals=[object[]]@();$architecture.viewer_contacts=[object[]]@()

$act1=@($architecture.acts)[0]
$act1.vc_ids=[object[]]@();$act1.nq_actions=[object[]]@();$act1.nr_actions=[object[]]@();$act1.open_nq_ids=[object[]]@();$act1.do_not_reveal=[object[]]@()
$act1.constraints=@(
    [ordered]@{cid='CID-001';source_field='ACT_FUNCTION';action='Zrealizuj funkcję aktu, zmianę stanu i most, a completion potraktuj jako kryterium odbioru tej samej transformacji';object_ids=@('ACT_FUNCTION:ACT-001','VIEWER_STATE:ACT-001','BRIDGE:ACT-001','COMPLETION:001');why_hard='Akt musi zmienić model widza';atomicity_reason='Jedna zależna transformacja aktu z jednym kryterium odbioru';verification='Stan wyjściowy, most i kryterium są spełnione'},
    [ordered]@{cid='CID-002';source_field='SW';action='Wykonaj jednostkę SW-001 z kompletem przypisanych dowodów';object_ids=@('SW:SW-001','REQUIRED:SW-001/#P-001');why_hard='Scena bez dowodu nie działa';atomicity_reason='Dowód zasila tę samą scenę';verification='SW-001 i karta występują razem'},
    [ordered]@{cid='CID-003';source_field='SW';action='Wykonaj jednostkę SW-002 z kompletem przypisanych dowodów';object_ids=@('SW:SW-002','REQUIRED:SW-002/#P-002');why_hard='Scena bez dowodu nie działa';atomicity_reason='Dowód zasila tę samą scenę';verification='SW-002 i karta występują razem'},
    [ordered]@{cid='CID-004';source_field='SW';action='Wykonaj jednostkę SW-003 z kompletem przypisanych dowodów';object_ids=@('SW:SW-003','REQUIRED:SW-003/#P-003');why_hard='Scena bez dowodu nie działa';atomicity_reason='Dowód zasila tę samą scenę';verification='SW-003 i karta występują razem'},
    [ordered]@{cid='CID-005';source_field='CONTINUITY_OUT';action='Zwróć pełny CONTINUITY_OUT';object_ids=@('CONTINUITY_OUT:ACT-001');why_hard='Bez stanu nie wolno odblokować kolejnego aktu';atomicity_reason='Jeden obowiązek protokołu';verification='OUT przechodzi schemat'}
)
foreach($scene in @($architecture.scene_weave)){$scene.nr_action='BRAK';$scene.nq_action='BRAK'}

$scene4=Copy-JsonObject $architecture.scene_weave[2]
$scene4.sw_id='SW-004';$scene4.act_id='ACT-002';$scene4.scene_or_unit='Scena SW-004';$scene4.function='Domknięcie modelu';$scene4.entry_knowledge_state='S3';$scene4.exit_knowledge_state='S4';$scene4.emotional_pressure='Presja SW-004';$scene4.local_stake='Stawka SW-004';$scene4.bridge_out='Koniec opowieści';$scene4.completion_criteria='Widz rozumie końcowy model';$scene4.required_evidence=@([ordered]@{p_id='#P-004';function='Dowód końcowy';necessity='Bez tego finał nie działa.'});$scene4.supporting_p_ids=[object[]]@();$scene4.reserve_p_ids=[object[]]@();$scene4.nq_action='BRAK';$scene4.nr_action='BRAK'
$architecture.scene_weave=@($architecture.scene_weave)+@($scene4)

$act2=Copy-JsonObject $act1
$act2.act_id='ACT-002';$act2.label='Akt drugi';$act2.act_function='Domknij model';$act2.entry_knowledge_state='S3';$act2.exit_knowledge_state='S4';$act2.intended_emotional_pressure_in=[string]$act1.intended_emotional_pressure_out;$act2.intended_emotional_pressure_out=('P'+'4');$act2.state_change_evidence='SW-004';$act2.failure_if_removed='Bez aktu nie ma finału';$act2.relative_weight='LIGHT';$act2.scene_weave_ids=@('SW-004');$act2.completion_criteria=@('Widz rozumie końcowy model.');$act2.bridge_out='Koniec opowieści';$act2.constraints=@(
    [ordered]@{cid='CID-001';source_field='ACT_FUNCTION';action='Zrealizuj funkcję aktu, zmianę stanu i most, a completion potraktuj jako kryterium odbioru tej samej transformacji';object_ids=@('ACT_FUNCTION:ACT-002','VIEWER_STATE:ACT-002','BRIDGE:ACT-002','COMPLETION:001');why_hard='Akt musi domknąć model widza';atomicity_reason='Jedna zależna transformacja aktu z jednym kryterium odbioru';verification='Stan wyjściowy, most i kryterium są spełnione'},
    [ordered]@{cid='CID-002';source_field='SW';action='Wykonaj jednostkę SW-004 z kompletem przypisanych dowodów';object_ids=@('SW:SW-004','REQUIRED:SW-004/#P-004');why_hard='Scena bez dowodu nie działa';atomicity_reason='Dowód zasila tę samą scenę';verification='SW-004 i karta występują razem'},
    [ordered]@{cid='CID-003';source_field='CONTINUITY_OUT';action='Zwróć pełny CONTINUITY_OUT';object_ids=@('CONTINUITY_OUT:ACT-002');why_hard='Bez stanu nie wolno domknąć aktu';atomicity_reason='Jeden obowiązek protokołu';verification='OUT przechodzi schemat'}
)
$architecture.acts=@($act1,$act2)

$architecturePath=Join-Path $cacheProject '02-architektura-odcinka.md'
$evidencePath=Join-Path $cacheProject '01-baza-dowodow.md'
Write-Architecture -Path $architecturePath -Architecture $architecture
$evidenceText=@'
| #S-001 | Źródło testowe |

### #P-001
TREŚĆ: Pierwszy ślad.
ŹRÓDŁO_ID: #S-001
LOKALIZACJA: strona 1
QA_K1: GOTOWA

### #P-002
TREŚĆ: Dokument zmienia model.
ŹRÓDŁO_ID: #S-001
LOKALIZACJA: strona 2
QA_K1: GOTOWA

### #P-003
TREŚĆ: Konsekwencja zmiany.
ŹRÓDŁO_ID: #S-001
LOKALIZACJA: strona 3
QA_K1: GOTOWA

### #P-004
TREŚĆ: Finał domyka model.
ŹRÓDŁO_ID: #S-001
LOKALIZACJA: strona 4
QA_K1: GOTOWA

### #P-005
TREŚĆ: Karta rezerwowa nieużywana przez żaden akt.
ŹRÓDŁO_ID: #S-001
LOKALIZACJA: strona 5
QA_K1: GOTOWA
'@
Write-Utf8Lf -Path $evidencePath -Text $evidenceText
$architectureState=Test-SystemV7NarrativeArchitecture -ArchitecturePath $architecturePath -EvidencePath $evidencePath
if(-not $architectureState.GateReady){throw "CACHE_ARCHITECTURE_NOT_GREEN: $($architectureState.ErrorDetails -join '; ')"}

$settingsPath=Join-Path $cacheRoot 'model-settings.json';Write-Utf8Lf -Path $settingsPath -Text '{"max_output_tokens":4096,"seed":42,"temperature":0}'
Set-Meta -Project $cacheProject -Values @{CURRENT_STAGE='K2B';LAST_GATE='K2_PASS'}
$null=& (Join-Path $tools 'Set-K3ModelManifest.ps1') -ProjectPath $cacheProject -ModelId 'CLAUDE-TEST' -ModelRevision 'CACHE-V1' -ModelSettingsPath $settingsPath
Set-Meta -Project $cacheProject -Values @{CURRENT_STAGE='K3';LAST_GATE='K2B_PASS'}
$baseline=& (Join-Path $tools 'Build-K3PacketsV2.ps1') -ProjectPath $cacheProject -ActId 'ACT-001' -VoiceProfilePath $VoiceProfilePath -Write
$packetPath=Join-Path $cacheProject '_work\k3\packets\ACT-001.packet.md';$baselineFileSha=Get-Hash $packetPath
$baselinePrefixSha=[string]$baseline.PrefixSha256

$architecture.acts[1].label='Akt drugi po lokalnej korekcie'
Write-Architecture -Path $architecturePath -Architecture $architecture
$afterOtherAct=& (Join-Path $tools 'Build-K3PacketsV2.ps1') -ProjectPath $cacheProject -ActId 'ACT-001' -VoiceProfilePath $VoiceProfilePath -Write -Force
$otherActStable=([string]$afterOtherAct.PacketSha256 -ceq [string]$baseline.PacketSha256) -and ((Get-Hash $packetPath) -ceq $baselineFileSha) -and ([string]$afterOtherAct.PrefixSha256 -ceq $baselinePrefixSha)

$evidenceText=$evidenceText.Replace('Karta rezerwowa nieużywana przez żaden akt.','Karta rezerwowa zmieniona, nadal nieużywana przez żaden akt.')
Write-Utf8Lf -Path $evidencePath -Text $evidenceText
$afterUnused=& (Join-Path $tools 'Build-K3PacketsV2.ps1') -ProjectPath $cacheProject -ActId 'ACT-001' -VoiceProfilePath $VoiceProfilePath -Write -Force
$unusedStable=([string]$afterUnused.PacketSha256 -ceq [string]$baseline.PacketSha256) -and ((Get-Hash $packetPath) -ceq $baselineFileSha) -and ([string]$afterUnused.PrefixSha256 -ceq $baselinePrefixSha)

$evidenceText=$evidenceText.Replace('Pierwszy ślad.','Pierwszy ślad po merytorycznej korekcie.')
Write-Utf8Lf -Path $evidencePath -Text $evidenceText
$afterSelected=& (Join-Path $tools 'Build-K3PacketsV2.ps1') -ProjectPath $cacheProject -ActId 'ACT-001' -VoiceProfilePath $VoiceProfilePath -Write -Force
$selectedInvalidated=([string]$afterSelected.PacketSha256 -cne [string]$baseline.PacketSha256) -and ((Get-Hash $packetPath) -cne $baselineFileSha) -and ([string]$afterSelected.PrefixSha256 -ceq $baselinePrefixSha)

# ---------------------------------------------------------------------------
# Reopen regression: local ACT-003 invalidation must preserve immutable bytes
# of ACT-001/002 plus prefix. Global K2B reopen must archive all K3 state.
# ---------------------------------------------------------------------------
function New-ReopenFixture([string]$Parent,[string]$Name){
    [IO.Directory]::CreateDirectory($Parent)|Out-Null
    $project=Join-Path $Parent $Name
    & (Join-Path $tools 'New-Project.ps1') -ProjectName $Name -DestinationRoot $Parent -NarrativeV2Pilot|Out-Null
    Set-Meta -Project $project -Values @{CURRENT_STAGE='K3';LAST_GATE='K2B_PASS';NARRATIVE_ACT_SEQUENCE='ACT-001,ACT-002,ACT-003';K3_PREFIX_SHA256=('A'*64);K3_LAST_ATTESTED_ACT='ACT-003';CONTINUITY_STATUS='PASS';LAST_STATE_RECEIPT_PATH='BRAK';LAST_STATE_RECEIPT_SHA256='BRAK'}
    $prefix=Join-Path $project '_work\k3\prefix\prefix.bundle.md';Write-Utf8Lf -Path $prefix -Text 'STABLE PREFIX SENTINEL'
    foreach($act in @('ACT-001','ACT-002','ACT-003')){
        Write-Utf8Lf -Path (Join-Path $project "_work\k3\packets\$act.packet.md") -Text "PACKET $act SENTINEL"
        Write-Utf8Lf -Path (Join-Path $project "_work\k3\acts\$act\prose.md") -Text "PROSE $act SENTINEL"
        Write-Utf8Lf -Path (Join-Path $project "_work\k3\beats\$act\state.json") -Text "{`"act`":`"$act`"}"
        Write-Utf8Lf -Path (Join-Path $project "_work\k3\continuity\$act.in.json") -Text "{`"act`":`"$act`",`"kind`":`"in`"}"
        Write-Utf8Lf -Path (Join-Path $project "_work\k3\continuity\$act.attest.json") -Text "{`"act`":`"$act`",`"kind`":`"attest`"}"
    }
    Write-Utf8Lf -Path (Join-Path $project '_work\k3\assembly\manifest.json') -Text '{"assembly":"sentinel"}'
    foreach($artifact in @('03-draft.md','04-raport-qa.md','04B-fact-check.md','05-FINAL-SCRIPT.md')){Write-Utf8Lf -Path (Join-Path $project $artifact) -Text "$artifact SENTINEL"}
    $project
}

$localProject=New-ReopenFixture -Parent (Join-Path $fixtureRoot 'reopen-local') -Name 'PROJECT-REOPEN-LOCAL'
$preserved=@{}
foreach($relative in @('_work\k3\prefix\prefix.bundle.md','_work\k3\packets\ACT-001.packet.md','_work\k3\acts\ACT-001\prose.md','_work\k3\continuity\ACT-001.attest.json','_work\k3\packets\ACT-002.packet.md','_work\k3\acts\ACT-002\prose.md','_work\k3\continuity\ACT-002.attest.json')){$preserved[$relative]=Get-Hash (Join-Path $localProject $relative)}
$localResult=& (Join-Path $tools 'Reopen-Stage.ps1') -ProjectPath $localProject -TargetStage k2b -ReasonCode Scene_Weave_Change -Scope 'Lokalna przebudowa wyłącznie ACT-003.' -FromActId ACT-003
$localBytesPreserved=$true;foreach($relative in $preserved.Keys){$path=Join-Path $localProject $relative;if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Hash $path) -cne [string]$preserved[$relative]){$localBytesPreserved=$false}}
$localAffectedRemoved=@(
    '_work\k3\packets\ACT-003.packet.md','_work\k3\acts\ACT-003','_work\k3\beats\ACT-003','_work\k3\continuity\ACT-003.in.json','_work\k3\continuity\ACT-003.attest.json','_work\k3\assembly','03-draft.md','04-raport-qa.md','04B-fact-check.md','05-FINAL-SCRIPT.md'
)|Where-Object{Test-Path -LiteralPath (Join-Path $localProject $_)}
$localArchiveComplete=(Test-Path -LiteralPath (Join-Path $localResult.ArchivePath 'k3\packets\ACT-003.packet.md') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $localResult.ArchivePath 'k3\acts\ACT-003') -PathType Container) -and (Test-Path -LiteralPath (Join-Path $localResult.ArchivePath 'canonical\03-draft.md') -PathType Leaf)
$localMetaPreserved=(Get-Meta $localProject 'NARRATIVE_ACT_SEQUENCE') -ceq 'ACT-001,ACT-002,ACT-003' -and (Get-Meta $localProject 'K3_PREFIX_SHA256') -ceq ('A'*64) -and (Get-Meta $localProject 'K3_LAST_ATTESTED_ACT') -ceq 'ACT-002'
$localHead=Get-StateReceiptHeadState -ProjectPath $localProject

$globalProject=New-ReopenFixture -Parent (Join-Path $fixtureRoot 'reopen-global') -Name 'PROJECT-REOPEN-GLOBAL'
$globalResult=& (Join-Path $tools 'Reopen-Stage.ps1') -ProjectPath $globalProject -TargetStage K2B -ReasonCode SCENE_WEAVE_CHANGE -Scope 'Globalna przebudowa całej architektury i wszystkich aktów.'
$globalK3Removed=-not(Test-Path -LiteralPath (Join-Path $globalProject '_work\k3'))
$globalArchiveComplete=(Test-Path -LiteralPath (Join-Path $globalResult.ArchivePath 'k3\prefix\prefix.bundle.md') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $globalResult.ArchivePath 'k3\acts\ACT-001\prose.md') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $globalResult.ArchivePath 'canonical\03-draft.md') -PathType Leaf)
$globalMetaCleared=(Get-Meta $globalProject 'NARRATIVE_ACT_SEQUENCE') -ceq 'BRAK' -and (Get-Meta $globalProject 'K3_PREFIX_SHA256') -ceq 'BRAK' -and (Get-Meta $globalProject 'K3_LAST_ATTESTED_ACT') -ceq 'BRAK'
$globalHead=Get-StateReceiptHeadState -ProjectPath $globalProject

[pscustomobject]@{
    CacheProjectPath=$cacheProject
    CacheArchitectureGateReady=$architectureState.GateReady
    OtherActPacketStable=$otherActStable
    UnusedEvidencePacketStable=$unusedStable
    SelectedEvidencePacketInvalidated=$selectedInvalidated
    PrefixStableAcrossLocalEdits=([string]$afterSelected.PrefixSha256 -ceq $baselinePrefixSha)
    LocalProjectPath=$localProject
    LocalReopenStatus=[string]$localResult.Status
    LocalFromActId=[string]$localResult.FromActId
    LocalBytesPreserved=$localBytesPreserved
    LocalAffectedRemoved=(@($localAffectedRemoved).Count -eq 0)
    LocalArchiveComplete=$localArchiveComplete
    LocalMetaPreserved=$localMetaPreserved
    LocalHeadValid=[bool]$localHead.Valid
    GlobalProjectPath=$globalProject
    GlobalReopenStatus=[string]$globalResult.Status
    GlobalFromActId=[string]$globalResult.FromActId
    GlobalK3Removed=$globalK3Removed
    GlobalArchiveComplete=$globalArchiveComplete
    GlobalMetaCleared=$globalMetaCleared
    GlobalHeadValid=[bool]$globalHead.Valid
}
