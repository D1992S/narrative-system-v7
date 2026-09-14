[CmdletBinding()]
param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][string]$SystemRoot)
# Read-only adapter: no mutation, stage/import/approval commands or LLM calls.
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $SystemRoot 'tools/Narrative-Receipts.ps1')
. (Join-Path $SystemRoot 'tools/K1-PublishIntegrity.ps1')
function Check([scriptblock]$Action) {
    try {$s=&$Action;@{valid=($s.Valid -eq $true);errors=@($s.Errors)}}
    catch {@{valid=$false;errors=@($_.Exception.Message)}}
}
$result=[ordered]@{origin=@{};runs=@{};acts=@{};lenses=@{};k4=@{};k5=@{};publication=@{}}
$result.origin=Check {Get-SystemV7ProjectOriginState -ProjectPath $project}
if(-not $result.origin.valid){$result|ConvertTo-Json -Depth 20 -Compress;exit 0}
$meta=Get-Content -LiteralPath (Join-Path $project 'meta.md') -Raw -Encoding UTF8
function Field($Name){Get-SystemV7NarrativeMetaField -Text $meta -Name $Name}
$runRoot=Join-Path $project '_work/narrative-runs'
if(Test-Path -LiteralPath $runRoot){
    foreach($d in Get-ChildItem -LiteralPath $runRoot -Directory){
        $receipt=Join-Path $d.FullName 'run-receipt.json'
        $manifest=Join-Path $d.FullName 'input-manifest.json'
        $r=@{valid=$false;bundle_valid=$false;errors=@()}
        if(Test-Path -LiteralPath $manifest){
            $b=Check {Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $manifest -RequireLiveSource}
            $r.bundle_valid=$b.valid;$r.errors=$b.errors
        }
        if(Test-Path -LiteralPath $receipt){
            $check=Check {Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $receipt -RequireLiveInputs}
            $r.valid=$check.valid;$r.errors=$check.errors
        }
        $result.runs[$d.Name]=$r
    }
}
$ids=@((Field 'NARRATIVE_ACT_SEQUENCE') -split ',' | ForEach-Object {$_.Trim()} | Where-Object {$_ -match '^ACT-\d{3}$'})
foreach($id in $ids){
    $dir=Join-Path $project "_work/k3/acts/$id"
    $a=@{}
    if(Test-Path -LiteralPath (Join-Path $dir 'prose.md')){
        $a.prose=Check {Get-SystemV7ActProseBindingState -ActId $id -BlocksPath (Join-Path $dir 'blocks.json') -ProsePath (Join-Path $dir 'prose.md')}
    }
    if(Test-Path -LiteralPath (Join-Path $project "_work/k3/continuity/$id.attest.json")){
        $a.attest=Check {Get-SystemV7ContinuityAttestState -ProjectPath $project -ActId $id}
    }
    $result.acts[$id]=$a
}
$draft=Join-Path $project '03-draft.md'
if(Test-Path -LiteralPath $draft){
    $draftSha=(Get-FileHash -LiteralPath $draft -Algorithm SHA256).Hash

    $result.assembly=Check {
        $draftText=Get-Content -LiteralPath $draft -Raw -Encoding UTF8
        $m=[regex]::Match($draftText,'(?m)^ASSEMBLY_MANIFEST_SHA256:\s*([A-F0-9]{64})\s*$')
        if(-not $m.Success){throw 'ASSEMBLY_POINTER_MISSING'}
        $assemblySha=$m.Groups[1].Value
        $assembly=Get-Content -LiteralPath (Join-Path $project "_work/k3/assembly/$assemblySha.json") -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
        $core=[ordered]@{};foreach($prop in $assembly.PSObject.Properties){if($prop.Name -ne 'assembly_manifest_sha256'){$core[$prop.Name]=$prop.Value}}
        if($assembly.schema -cne 'K3_ASSEMBLY_MANIFEST_V1' -or (Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $core)) -cne $assemblySha){throw 'ASSEMBLY_BINDING_INVALID'}
        if($assembly.prefix_sha256 -cne (Field 'K3_PREFIX_SHA256') -or $assembly.model_id -cne (Field 'K3_MODEL_ID') -or $assembly.model_revision -cne (Field 'K3_MODEL_REVISION')){throw 'ASSEMBLY_MODEL_STALE'}
        if((@($assembly.acts|ForEach-Object{$_.act_id}) -join ',') -cne ($ids -join ',')){throw 'ASSEMBLY_ACT_SEQUENCE_STALE'}
        foreach($entry in $assembly.acts){
            $id=[string]$entry.act_id
            if(-not $result.acts[$id].attest.valid){throw "ASSEMBLY_ATTEST_INVALID: $id"}
            foreach($pair in @(@("_work/k3/acts/$id/prose.md",$entry.prose_sha256),@("_work/k3/acts/$id/blocks.json",$entry.blocks_sha256),@("_work/k3/continuity/$id.attest.json",$entry.attest_sha256))){
                if((Get-FileHash -LiteralPath (Join-Path $project $pair[0]) -Algorithm SHA256).Hash -cne $pair[1]){throw 'ASSEMBLY_ARTIFACT_STALE'}
            }
        }
        $narration=[regex]::Match($draftText,'(?ms)^## NARRACJA ROBOCZA\s*\r?\n(?<body>.*)$')
        if(-not $narration.Success -or (Get-SystemV7NarrativeSha256Text -Text ((ConvertTo-SystemV7LfText $narration.Groups['body'].Value).Trim()+[char]10)) -cne $assembly.narration_sha256){throw 'ASSEMBLY_NARRATION_STALE'}
        $map=[regex]::Match($draftText,'(?s)<!-- K3_BLOCK_MAP_BEGIN -->\s*\x60{3}json\s*(.*?)\s*\x60{3}\s*<!-- K3_BLOCK_MAP_END -->')
        if(-not $map.Success){throw 'ASSEMBLY_BLOCK_MAP_MISSING'}
        $mapData=$map.Groups[1].Value|ConvertFrom-Json -DateKind String -Depth 64
        if((Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson $mapData)) -cne $assembly.block_map_content_sha256){throw 'ASSEMBLY_BLOCK_MAP_STALE'}
        [pscustomobject]@{Valid=$true;Errors=@()}
    }
    foreach($lens in @('EDITOR','VERIFY','COLD_READER')){
        $relative=Field ("K4_"+$lens+"_PROOF")
        if($relative -and $relative -ne 'BRAK'){
            $result.lenses[$lens]=Check {
                $path=Resolve-K1PublishRelativePath -ProjectPath $project -RelativePath $relative -Code 'PANEL_PROOF'
                Get-SystemV7K4LensProofResolutionState -ProjectPath $project -Lens $lens -ProofPath $path -DraftSha256 $draftSha
            }
        }
    }
    $proofSha=Field 'K4_PROOF_SET_SHA256'
    if($proofSha -match '^[A-F0-9]{64}$'){
        $result.k4=Check {Get-SystemV7K4ProofSetState -ProjectPath $project -ProofSetSha256 $proofSha -ExpectedDraftSha256 $draftSha}
    }
}
if(Test-Path -LiteralPath (Join-Path $project '_work/K5')){
    $result.k5=Check {Get-SystemV7K5ApprovalV2State -ProjectPath $project}
}
$receiptRelative=Field 'K1_PUBLISH_RECEIPT_PATH'
if($receiptRelative -and $receiptRelative -ne 'BRAK'){
    $result.publication=Check {
        $null=Assert-K1PublishReceiptCurrent -ProjectPath $project -ReceiptRelative $receiptRelative -ExpectedReceiptSha256 (Field 'K1_PUBLISH_RECEIPT_SHA256')
        [pscustomobject]@{Valid=$true;Errors=@()}
    }
}
$result|ConvertTo-Json -Depth 20 -Compress
