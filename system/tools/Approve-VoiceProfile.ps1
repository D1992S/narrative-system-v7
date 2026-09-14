[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][string]$ExemplarSpecPath,
    [Parameter(Mandatory)][string]$ApprovalNote,
    [switch]$DawidApproved
)

$ErrorActionPreference='Stop'
$systemRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$profileRoot=[IO.Path]::GetFullPath((Join-Path $systemRoot '_SYSTEM\NARRATIVE\VOICE-PROFILES'))
$profile=[IO.Path]::GetFullPath($ProfilePath)
$specPath=[IO.Path]::GetFullPath($ExemplarSpecPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
Assert-SystemV7NarrativeInstructionContract -SystemRoot $systemRoot | Out-Null

if(-not $DawidApproved){throw 'VOICE_PROFILE_REQUIRES_EXPLICIT_DAWID_APPROVAL'}
if(-not(Test-SystemV7ConcreteText -Value $ApprovalNote) -or $ApprovalNote.Trim().Length -lt 12){throw 'VOICE_PROFILE_APPROVAL_NOTE_NOT_CONCRETE'}
$profilePrefix=$profileRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
if(-not $profile.StartsWith($profilePrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'VOICE_PROFILE_PATH_OUTSIDE_PROFILE_ROOT'}
if(-not(Test-Path -LiteralPath $profile -PathType Leaf)){throw 'VOICE_PROFILE_CANDIDATE_MISSING'}
if(-not(Test-Path -LiteralPath $specPath -PathType Leaf)){throw 'VOICE_EXEMPLAR_SPEC_MISSING'}
Assert-SystemV7PathNoReparse -Path $profile -ContainmentRoot $profileRoot|Out-Null
Assert-SystemV7PathNoReparse -Path $specPath|Out-Null

function Get-StrictUtf8([string]$Path){
    try{return [Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($Path))}
    catch{throw "STRICT_UTF8_REQUIRED: $Path"}
}
function Get-OnlyHeader([string]$Text,[string]$Name){
    $matches=@([regex]::Matches($Text,"(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$"))
    if($matches.Count -ne 1){throw "VOICE_PROFILE_HEADER_FIELD_COUNT_INVALID: $Name"}
    return $matches[0].Groups[1].Value.Trim()
}
function Assert-ExactFields([object]$Object,[string[]]$Expected,[string]$Scope){
    $actual=@($Object.PSObject.Properties.Name)
    if($actual.Count -ne $Expected.Count -or @(Compare-Object -ReferenceObject $Expected -DifferenceObject $actual).Count -gt 0){throw "$Scope`_FIELDS_INVALID"}
}

$candidateBytes=[IO.File]::ReadAllBytes($profile)
$candidateText=ConvertTo-SystemV7LfText -Text (Get-StrictUtf8 $profile)
$profileRevision=Get-OnlyHeader $candidateText 'VOICE_PROFILE_REVISION'
if((Get-OnlyHeader $candidateText 'VOICE_PROFILE_SCHEMA') -cne 'SYSTEM_V7_VOICE_PROFILE_V1' -or
   (Get-OnlyHeader $candidateText 'STATUS') -cne 'CANDIDATE' -or
   (Get-OnlyHeader $candidateText 'APPROVED_BY') -cne 'BRAK' -or
   (Get-OnlyHeader $candidateText 'APPROVAL_RECEIPT_PATH') -cne 'BRAK' -or
   (Get-OnlyHeader $candidateText 'APPROVAL_RECEIPT_SHA256') -cne 'BRAK'){
    $existing=Get-SystemV7VoiceProfileState -ProfilePath $profile
    if($existing.Valid){
        [pscustomobject]@{Status='VOICE_PROFILE_ALREADY_APPROVED';ProfilePath=$profile;Revision=$existing.Revision;ProfileSha256=$existing.ProfileSha256}
        return
    }
    throw 'VOICE_PROFILE_NOT_PRISTINE_CANDIDATE'
}
if($profileRevision -notmatch '^[A-Z0-9][A-Z0-9._-]{2,80}$'){throw 'VOICE_PROFILE_REVISION_INVALID'}
$rulesMatch=[regex]::Match($candidateText,'(?ms)^##\s+VOICE RULES\s*\n(?<body>.*?)(?=^##\s+VOICE EXEMPLARS\s*$)')
if(-not $rulesMatch.Success){throw 'VOICE_RULES_MISSING'}
$rules=(ConvertTo-SystemV7LfText -Text $rulesMatch.Groups['body'].Value).Trim()+"`n"
if(-not(Test-SystemV7ConcreteText -Value $rules)){throw 'VOICE_RULES_NOT_CONCRETE'}

try{$spec=(Get-StrictUtf8 $specPath)|ConvertFrom-Json -DateKind String -Depth 64}catch{throw "VOICE_EXEMPLAR_SPEC_INVALID_JSON: $($_.Exception.Message)"}
Assert-ExactFields $spec @('schema','voice_profile_revision','exemplars') 'VOICE_EXEMPLAR_SPEC'
if([string]$spec.schema -cne 'VOICE_EXEMPLAR_APPROVAL_INPUT_V1' -or [string]$spec.voice_profile_revision -cne $profileRevision){throw 'VOICE_EXEMPLAR_SPEC_BINDING_INVALID'}
$items=@($spec.exemplars)
if($items.Count -eq 0){throw 'VOICE_EXEMPLAR_SPEC_EMPTY'}
$allowed=@('STRONG_OPENING','SCENE','UNCERTAINTY','KNOWLEDGE_BOUNDARY','VIEWER_CONTACT','TRANSITION','PAYOFF')
$coverage=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$exactHashes=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$projectRoots=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($item in $items){
    Assert-ExactFields $item @('exemplar_id','project_name','artifact_path','exact_text','demonstrates') 'VOICE_EXEMPLAR_INPUT'
    $id=[string]$item.exemplar_id
    if($id -notmatch '^EX-\d{3}$' -or -not $ids.Add($id)){throw "VOICE_EXEMPLAR_ID_INVALID_OR_DUPLICATE: $id"}
    $artifact=[IO.Path]::GetFullPath([string]$item.artifact_path)
    if([IO.Path]::GetFileName($artifact) -cne '05-FINAL-SCRIPT.md'){throw "VOICE_EXEMPLAR_NOT_FINAL_SCRIPT: $id"}
    $null=$projectRoots.Add((Split-Path -Parent $artifact))
    $functions=@([string[]]@($item.demonstrates));$local=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if($functions.Count -eq 0){throw "VOICE_EXEMPLAR_FUNCTIONS_EMPTY: $id"}
    foreach($function in $functions){if($function -notin $allowed -or -not $local.Add($function)){throw "VOICE_EXEMPLAR_FUNCTION_INVALID: $id/$function"};$null=$coverage.Add($function)}
    $exact=(ConvertTo-SystemV7LfText -Text ([string]$item.exact_text)).Trim()
    if(-not(Test-SystemV7ConcreteText -Value $exact)){throw "VOICE_EXEMPLAR_TEXT_NOT_CONCRETE: $id"}
    $exactSha=Get-SystemV7NarrativeSha256Text -Text ($exact+"`n")
    if(-not $exactHashes.Add($exactSha)){throw "VOICE_EXEMPLAR_TEXT_DUPLICATE: $id"}
}
foreach($function in $allowed){if(-not $coverage.Contains($function)){throw "VOICE_EXEMPLAR_FUNCTION_COVERAGE_MISSING: $function"}}

$lockPath=Join-Path $profileRoot '.voice-profile.lock'
$systemLock=$null;$projectLocks=[Collections.Generic.List[IDisposable]]::new();$backupCreated=$false;$receiptCreated=$false;$profileReplaced=$false
$approvalDirectory=Join-Path $profileRoot '_APPROVALS'
$receiptPath=$null;$backupPath=$null
try{
    [IO.Directory]::CreateDirectory($profileRoot)|Out-Null
    $systemLock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    foreach($root in @($projectRoots|Sort-Object)){$projectLocks.Add((Enter-SystemV7ProjectMetaLock -ProjectPath $root))}
    if((Get-FileHash -LiteralPath $profile -Algorithm SHA256).Hash -cne [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($candidateBytes))){throw 'VOICE_PROFILE_CANDIDATE_CHANGED_DURING_APPROVAL'}

    $registryItems=[Collections.Generic.List[object]]::new();$sourceBindings=[Collections.Generic.List[object]]::new();$compiled=[Collections.Generic.List[string]]::new()
    foreach($item in @($items|Sort-Object { [string]$_.exemplar_id })){
        $id=[string]$item.exemplar_id;$artifact=[IO.Path]::GetFullPath([string]$item.artifact_path);$projectRoot=Split-Path -Parent $artifact
        foreach($path in @($artifact,(Join-Path $projectRoot 'meta.md'))){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "VOICE_EXEMPLAR_REQUIRED_FILE_MISSING: $id/$path"};Assert-SystemV7PathNoReparse -Path $path -ContainmentRoot $projectRoot|Out-Null}
        $metaText=Get-Content -LiteralPath (Join-Path $projectRoot 'meta.md') -Raw -Encoding UTF8
        $workflow=Get-SystemV7SingleMetaField -Text $metaText -Name 'WORKFLOW_REVISION';$projectName=Get-SystemV7SingleMetaField -Text $metaText -Name 'PROJECT_NAME'
        if($projectName -cne [string]$item.project_name){throw "VOICE_EXEMPLAR_PROJECT_NAME_MISMATCH: $id"}
        $origin=Assert-SystemV7CurrentProjectOrigin -ProjectPath $projectRoot -MetaText $metaText
        $artifactText=ConvertTo-SystemV7LfText -Text (Get-StrictUtf8 $artifact)
        $status=@([regex]::Matches($artifactText,'(?m)^STATUS:\s*(.*?)\s*$'))
        if($status.Count -ne 1 -or $status[0].Groups[1].Value.Trim() -cne 'ZATWIERDZONY'){throw "VOICE_EXEMPLAR_FINAL_NOT_DAWID_APPROVED: $id"}
        $exact=(ConvertTo-SystemV7LfText -Text ([string]$item.exact_text)).Trim()
        if($artifactText.IndexOf($exact,[StringComparison]::Ordinal) -lt 0){throw "VOICE_EXEMPLAR_TEXT_NOT_VERBATIM_IN_FINAL: $id"}
        $artifactSha=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash;$exactSha=Get-SystemV7NarrativeSha256Text -Text ($exact+"`n")
        if($workflow -ceq $script:SystemV7NarrativeWorkflowRevision){$k5=Get-SystemV7K5ApprovalV2State -ProjectPath $projectRoot;$k5Path=[string]$k5.Path;$k5Sha=[string]$k5.Sha256}
        elseif($workflow -ceq $script:SystemV7PreviousProjectWorkflowRevision){$k5=Get-K5ApprovalReceiptState -ProjectPath $projectRoot;$k5Path=[string]$k5.ReceiptPath;$k5Sha=[string]$k5.ReceiptSha256}
        else{throw "VOICE_EXEMPLAR_WORKFLOW_UNSUPPORTED: $id/$workflow"}
        if(-not $k5.Valid){throw "VOICE_EXEMPLAR_K5_APPROVAL_INVALID: $id/$($k5.Errors -join '; ')"}
        $functions=[string[]]@($item.demonstrates);[Array]::Sort($functions,[StringComparer]::Ordinal)
        $registryItems.Add([ordered]@{exemplar_id=$id;project_name=$projectName;artifact_path=$artifact;artifact_sha256=$artifactSha;exact_text_sha256=$exactSha;approval_status='DAWID_APPROVED';demonstrates=$functions;exact_text=$exact})
        $sourceBindings.Add([ordered]@{exemplar_id=$id;project_name=$projectName;project_origin_sha256=[string]$origin.Sha256;workflow_revision=$workflow;artifact_path=$artifact;artifact_sha256=$artifactSha;k5_approval_receipt_path=$k5Path;k5_approval_receipt_sha256=$k5Sha;exact_text_sha256=$exactSha})
        $compiled.Add($exact)
    }
    $wordCount=@([regex]::Matches(($compiled -join "`n`n"),"\b[\p{L}\p{N}][\p{L}\p{N}\p{M}’'-]*\b")).Count
    if($wordCount -lt 300 -or $wordCount -gt 500){throw "VOICE_EXEMPLARS_WORD_COUNT_OUTSIDE_300_500: $wordCount"}
    $registry=[ordered]@{schema='VOICE_EXEMPLAR_REGISTRY_V1';exemplars=@($registryItems)}
    $registryJson=ConvertTo-SystemV7CanonicalJson -Value $registry;$rulesSha=Get-SystemV7NarrativeSha256Text -Text $rules;$registrySha=Get-SystemV7NarrativeSha256Text -Text $registryJson;$exemplars=($compiled -join "`n`n")+"`n";$exemplarsSha=Get-SystemV7NarrativeSha256Text -Text $exemplars
    $profileRelative=[IO.Path]::GetRelativePath($systemRoot,$profile).Replace('\','/')
    [IO.Directory]::CreateDirectory($approvalDirectory)|Out-Null
    $receiptPath=Join-Path $approvalDirectory "$profileRevision-$registrySha-approval.json"
    $backupPath=Join-Path $approvalDirectory "$profileRevision-$([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($candidateBytes)))-candidate.md"
    $approvedAt=[DateTime]::UtcNow.ToString('o')
    $receipt=[ordered]@{schema='SYSTEM_V7_VOICE_PROFILE_APPROVAL_V1';actor='DAWID';attestation_scope='RULES_AND_EXACT_EXEMPLARS';voice_profile_revision=$profileRevision;profile_relative=$profileRelative;rules_sha256=$rulesSha;exemplar_registry_sha256=$registrySha;exemplars_sha256=$exemplarsSha;exemplar_sources=@($sourceBindings);approval_note=$ApprovalNote.Trim();approved_at_utc=$approvedAt}
    $receipt['binding_sha256']=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $receipt)
    $receiptText=ConvertTo-SystemV7CanonicalJson -Value $receipt;$receiptSha=Get-SystemV7NarrativeSha256Text -Text $receiptText;$receiptRelative=[IO.Path]::GetRelativePath($systemRoot,$receiptPath).Replace('\','/')
    $fence='```'
    $approvedProfile="# Profil głosu Dawida — $profileRevision`n`nVOICE_PROFILE_SCHEMA: SYSTEM_V7_VOICE_PROFILE_V1`nVOICE_PROFILE_REVISION: $profileRevision`nSTATUS: APPROVED`nAPPROVED_BY: DAWID`nAPPROVAL_RECEIPT_PATH: $receiptRelative`nAPPROVAL_RECEIPT_SHA256: $receiptSha`nRULES_SHA256: $rulesSha`nEXEMPLAR_REGISTRY_SHA256: $registrySha`nEXEMPLARS_SHA256: $exemplarsSha`n`n## VOICE RULES`n`n$rules`n## VOICE EXEMPLARS`n`n${fence}json`n$registryJson$fence`n"

    Write-BytesCreateNewAtomic -Path $backupPath -Bytes $candidateBytes;$backupCreated=$true
    Write-BytesCreateNewAtomic -Path $receiptPath -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($receiptText));$receiptCreated=$true
    Write-SystemV7NarrativeAtomicText -Path $profile -Text $approvedProfile|Out-Null;$profileReplaced=$true
    $state=Get-SystemV7VoiceProfileState -ProfilePath $profile
    if(-not $state.Valid){throw "VOICE_PROFILE_POSTVALIDATION_FAILED: $($state.Errors -join '; ')"}
    [pscustomobject]@{Status='VOICE_PROFILE_APPROVED';ProfilePath=$profile;Revision=$state.Revision;ProfileSha256=$state.ProfileSha256;ReceiptPath=$receiptPath;ReceiptSha256=$receiptSha;ExemplarCount=$registryItems.Count;ExemplarWordCount=$wordCount}
}catch{
    if($profileReplaced){Write-SystemV7NarrativeAtomicText -Path $profile -Text $candidateText|Out-Null}
    if($receiptCreated -and $receiptPath -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)){[IO.File]::Delete($receiptPath)}
    if($backupCreated -and $backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf)){[IO.File]::Delete($backupPath)}
    throw
}finally{
    for($i=$projectLocks.Count-1;$i -ge 0;$i--){$projectLocks[$i].Dispose()}
    if($systemLock){$systemLock.Dispose()}
}
