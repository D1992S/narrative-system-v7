[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [switch]$SaveBaseline,
    [string]$OldDraftPath,
    [string]$NewDraftPath,
    [switch]$WriteImpact
)
$ErrorActionPreference='Stop';$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1');. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1');. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$metaPath=Join-Path $project 'meta.md';$meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8;$origin=if($SaveBaseline -or $WriteImpact){Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta}else{Assert-SystemV7CurrentProjectOrigin -ProjectPath $project -MetaText $meta}
$draftPath=if($NewDraftPath){[IO.Path]::GetFullPath($NewDraftPath)}else{Join-Path $project '03-draft.md'}
if(-not(Test-Path -LiteralPath $draftPath -PathType Leaf)){throw 'NEW_DRAFT_MISSING'};$draftRelative=Get-SystemV7NarrativeRelativePath -Root $project -Path $draftPath;$null=Assert-SystemV7PathNoReparse -Path $draftPath -ContainmentRoot $project
if(($SaveBaseline -or $WriteImpact) -and $draftRelative -cne '03-draft.md'){throw 'MUTATING_COMPARE_REQUIRES_CANONICAL_03_DRAFT'}
$baselineDir=Join-Path $project '_work\k4\baselines';$impactDir=Join-Path $project '_work\k4\impact'
$readSnapshot={param([string]$Path)$bytes=[IO.File]::ReadAllBytes($Path);$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));try{$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)}catch{throw "DRAFT_NOT_VALID_UTF8: $Path"};[pscustomobject]@{Bytes=$bytes;Sha256=$sha;Text=(ConvertTo-SystemV7LfText -Text $text)}}

if($SaveBaseline){
    $snapshot=&$readSnapshot $draftPath;$target=Join-Path $baselineDir "$($snapshot.Sha256).md";$receipt=Join-Path $baselineDir "$($snapshot.Sha256).receipt.json";$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
    $targetCreated=$false;$receiptCreated=$false
    try{
        if((Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash -cne $snapshot.Sha256){throw 'BASELINE_DRAFT_COMPARE_AND_SWAP_CONFLICT'}
        $null=Assert-SystemV7PathNoReparse -Path $baselineDir -ContainmentRoot $project;[IO.Directory]::CreateDirectory($baselineDir)|Out-Null
        if(-not(Test-Path -LiteralPath $target -PathType Leaf)){[IO.File]::WriteAllBytes($target,$snapshot.Bytes);$targetCreated=$true}elseif((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $snapshot.Sha256){throw 'BASELINE_HASH_COLLISION'}
        if(-not(Test-Path -LiteralPath $receipt -PathType Leaf)){$record=[ordered]@{schema='SYSTEM_V7_QA_BASELINE_RECEIPT_V2';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;project_origin_sha256=$origin.Sha256;baseline_relative=(Get-SystemV7NarrativeRelativePath -Root $project -Path $target);baseline_sha256=$snapshot.Sha256;created_at_utc=[DateTime]::UtcNow.ToString('o')};$record['binding_sha256']=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $record);Write-SystemV7NarrativeCreateNewJson -Path $receipt -Value $record|Out-Null;$receiptCreated=$true}
        else{$existing=Get-Content -LiteralPath $receipt -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String;if([string]$existing.baseline_sha256 -cne $snapshot.Sha256){throw 'BASELINE_RECEIPT_COLLISION'}}
    }catch{if($receiptCreated -and (Test-Path -LiteralPath $receipt -PathType Leaf)){[IO.File]::Delete($receipt)};if($targetCreated -and (Test-Path -LiteralPath $target -PathType Leaf)){[IO.File]::Delete($target)};throw}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
    [pscustomobject]@{Status='IMMUTABLE_BASELINE_SAVED';BaselinePath=$target;BaselineSha256=$snapshot.Sha256;ReceiptPath=$receipt};return
}
if(-not $OldDraftPath){$latest=@(Get-ChildItem -LiteralPath $baselineDir -Filter '*.md' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1);if($latest.Count -ne 1){throw 'OLD_DRAFT_OR_BASELINE_REQUIRED'};$OldDraftPath=$latest[0].FullName}
$old=[IO.Path]::GetFullPath($OldDraftPath);if(-not(Test-Path -LiteralPath $old -PathType Leaf)){throw 'OLD_DRAFT_MISSING'};$oldRelative=Get-SystemV7NarrativeRelativePath -Root $project -Path $old;$null=Assert-SystemV7PathNoReparse -Path $old -ContainmentRoot $project
if($WriteImpact -and $oldRelative -cnotmatch '^_work/k4/baselines/[A-F0-9]{64}\.md$'){throw 'WRITE_IMPACT_REQUIRES_IMMUTABLE_BASELINE'}
$oldSnapshot=&$readSnapshot $old;$newSnapshot=&$readSnapshot $draftPath
if($oldRelative -cmatch '^_work/k4/baselines/(?<sha>[A-F0-9]{64})\.md$' -and [string]$Matches.sha -cne $oldSnapshot.Sha256){throw 'BASELINE_FILENAME_SHA_MISMATCH'}
$class=if($oldSnapshot.Sha256 -ceq $newSnapshot.Sha256){'BYTE_IDENTICAL'}else{'SEMANTIC_REVIEW_REQUIRED'}
$extractMap={param($t)$m=[regex]::Match($t,'(?s)<!--\s*K3_BLOCK_MAP_BEGIN\s*-->\s*```json\s*(?<json>.*?)\s*```\s*<!--\s*K3_BLOCK_MAP_END\s*-->');if($m.Success){$m.Groups['json'].Value|ConvertFrom-Json -DateKind String -Depth 64}else{$null}}
$oldMap=&$extractMap $oldSnapshot.Text;$newMap=&$extractMap $newSnapshot.Text;$changed=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$oldBlocks=@{};if($oldMap){foreach($a in @($oldMap.acts)){foreach($b in @($a.blocks)){$oldBlocks[[string]$b.block_id]=[string]$b.block_sha256}}};$newBlocks=@{};if($newMap){foreach($a in @($newMap.acts)){foreach($b in @($a.blocks)){$newBlocks[[string]$b.block_id]=[string]$b.block_sha256}}}
foreach($id in @($oldBlocks.Keys+$newBlocks.Keys|Select-Object -Unique)){if(-not $oldBlocks.ContainsKey($id) -or -not $newBlocks.ContainsKey($id) -or [string]$oldBlocks[$id] -cne [string]$newBlocks[$id]){$null=$changed.Add($id)}}
$oldWords=@([regex]::Matches($oldSnapshot.Text,'\b[\p{L}\p{N}]+\b')).Count;$newWords=@([regex]::Matches($newSnapshot.Text,'\b[\p{L}\p{N}]+\b')).Count;$scope=[math]::Round(100*[math]::Abs($newWords-$oldWords)/[math]::Max(1,$oldWords),1)
$decisions=if($class -ceq 'BYTE_IDENTICAL'){[ordered]@{EDITOR='CARRYFORWARD_ALLOWED';VERIFY='CARRYFORWARD_ALLOWED';COLD_READER='CARRYFORWARD_ALLOWED'}}else{[ordered]@{EDITOR='RERUN_REQUIRED';VERIFY='RERUN_REQUIRED';COLD_READER='RERUN_REQUIRED'}}
$impactCore=[ordered]@{schema='QA_IMPACT_V1';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;project_origin_sha256=$origin.Sha256;old_draft_relative=$oldRelative;old_draft_sha256=$oldSnapshot.Sha256;new_draft_relative=$draftRelative;new_draft_sha256=$newSnapshot.Sha256;change_class=$class;changed_block_ids=@($changed|Sort-Object);word_count_delta_percent=$scope;over_twenty_percent=($scope -gt 20);decisions=$decisions;impact_review_required=($class -ceq 'SEMANTIC_REVIEW_REQUIRED')}
$diffSha=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $impactCore);$impact=[ordered]@{};foreach($k in $impactCore.Keys){$impact[$k]=$impactCore[$k]};$impact['diff_sha256']=$diffSha;$path=Join-Path $impactDir "$diffSha.impact.json"
if($WriteImpact){
    $lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project;$created=$false
    try{if((Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash -cne $oldSnapshot.Sha256 -or (Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash -cne $newSnapshot.Sha256){throw 'QA_IMPACT_COMPARE_AND_SWAP_CONFLICT'};$null=Assert-SystemV7PathNoReparse -Path $impactDir -ContainmentRoot $project;[IO.Directory]::CreateDirectory($impactDir)|Out-Null;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Write-SystemV7NarrativeCreateNewJson -Path $path -Value $impact|Out-Null;$created=$true}else{$existing=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;if((ConvertTo-SystemV7CanonicalJson -Value $existing) -cne (ConvertTo-SystemV7CanonicalJson -Value $impact)){throw 'QA_IMPACT_COLLISION'}}}catch{if($created -and (Test-Path -LiteralPath $path -PathType Leaf)){[IO.File]::Delete($path)};throw}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
}
[pscustomobject]@{Status=if($class -ceq 'BYTE_IDENTICAL'){'MECHANICAL_CLASSIFICATION_COMPLETE'}else{'SEMANTIC_REVIEW_REQUIRED'};ChangeClass=$class;OldDraftSha256=$oldSnapshot.Sha256;NewDraftSha256=$newSnapshot.Sha256;DiffSha256=$diffSha;ChangedBlockIds=@($changed|Sort-Object);ChangeScopePercent=$scope;EditorDecision=$decisions.EDITOR;VerifyDecision=$decisions.VERIFY;ColdReaderDecision=$decisions.COLD_READER;ImpactPath=if($WriteImpact){$path}else{'NOT_WRITTEN'}}
