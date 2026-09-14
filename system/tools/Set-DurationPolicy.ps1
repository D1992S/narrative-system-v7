[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateSet('GUIDE','HARD_MAX')][string]$Mode,
    [Parameter(Mandatory)][ValidateRange(1,240)][int]$TargetMinutes,
    [Parameter(Mandatory)][string]$Reason,
    [switch]$DawidApproved
)
$ErrorActionPreference='Stop';if(-not $DawidApproved){throw 'DAWID_APPROVAL_REQUIRED'};if($Reason.Trim().Length -lt 12){throw 'DURATION_POLICY_REASON_NOT_CONCRETE'}
$Mode=$Mode.ToUpperInvariant()
$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1');. (Join-Path $PSScriptRoot 'Narrative-V2.ps1');. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1');. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null

function Repair-SystemV7DurationTransactions {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $transactionRoot=Join-Path $ProjectRoot '.system-v7\duration-transactions'
    if(-not(Test-Path -LiteralPath $transactionRoot -PathType Container)){return}
    $metaCurrent=Join-Path $ProjectRoot 'meta.md';$fundamentCurrent=Join-Path $ProjectRoot '00-fundament-projektu.md'
    foreach($transaction in @(Get-ChildItem -LiteralPath $transactionRoot -Directory -Force|Sort-Object Name)){
        $preparedPath=Join-Path $transaction.FullName 'PREPARED.json';$committedPath=Join-Path $transaction.FullName 'COMMITTED.json';$abortedPath=Join-Path $transaction.FullName 'ABORTED.json'
        if(-not(Test-Path -LiteralPath $preparedPath -PathType Leaf) -or (Test-Path -LiteralPath $committedPath -PathType Leaf) -or (Test-Path -LiteralPath $abortedPath -PathType Leaf)){continue}
        try{$prepared=Get-Content -LiteralPath $preparedPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 32}catch{throw "DURATION_TRANSACTION_PREPARED_INVALID: $($transaction.FullName)"}
        if([string]$prepared.schema -cne 'SYSTEM_V7_DURATION_TRANSACTION_V2'){throw "DURATION_TRANSACTION_SCHEMA_UNSUPPORTED: $($transaction.FullName)"}
        $metaBefore=Join-Path $transaction.FullName 'meta.before';$fundamentBefore=Join-Path $transaction.FullName 'fundament.before'
        foreach($backup in @(@($metaBefore,[string]$prepared.input_meta_sha256),@($fundamentBefore,[string]$prepared.input_fundament_sha256))){if(-not(Test-Path -LiteralPath $backup[0] -PathType Leaf) -or (Get-FileHash -LiteralPath $backup[0] -Algorithm SHA256).Hash -cne $backup[1]){throw "DURATION_TRANSACTION_BACKUP_INVALID: $($transaction.FullName)"}}
        $currentMetaSha=(Get-FileHash -LiteralPath $metaCurrent -Algorithm SHA256).Hash;$currentFundamentSha=(Get-FileHash -LiteralPath $fundamentCurrent -Algorithm SHA256).Hash
        $atResult=$currentMetaSha -ceq [string]$prepared.result_meta_sha256 -and $currentFundamentSha -ceq [string]$prepared.result_fundament_sha256
        $atInput=$currentMetaSha -ceq [string]$prepared.input_meta_sha256 -and $currentFundamentSha -ceq [string]$prepared.input_fundament_sha256
        if($atResult){
            Write-SystemV7NarrativeCreateNewJson -Path $committedPath -Value ([ordered]@{status='COMMITTED_RECOVERED';completed_at_utc=[DateTime]::UtcNow.ToString('o')})|Out-Null
            continue
        }
        $knownPartial=($currentMetaSha -in @([string]$prepared.input_meta_sha256,[string]$prepared.result_meta_sha256)) -and ($currentFundamentSha -in @([string]$prepared.input_fundament_sha256,[string]$prepared.result_fundament_sha256))
        if(-not $atInput -and -not $knownPartial){throw "DURATION_TRANSACTION_CONFLICT_REQUIRES_MANUAL_REVIEW: $($transaction.FullName)"}
        if(-not $atInput){[IO.File]::WriteAllBytes($metaCurrent,[IO.File]::ReadAllBytes($metaBefore));[IO.File]::WriteAllBytes($fundamentCurrent,[IO.File]::ReadAllBytes($fundamentBefore))}
        if([bool]$prepared.receipt_created -and (Test-SystemV7ConcreteText ([string]$prepared.receipt_relative))){
            $receipt=Join-Path $ProjectRoot ([string]$prepared.receipt_relative);$null=Get-SystemV7NarrativeRelativePath -Root $ProjectRoot -Path $receipt
            if((Test-Path -LiteralPath $receipt -PathType Leaf) -and (Get-FileHash -LiteralPath $receipt -Algorithm SHA256).Hash -ceq [string]$prepared.receipt_sha256){[IO.File]::Delete($receipt)}
        }
        Write-SystemV7NarrativeCreateNewJson -Path $abortedPath -Value ([ordered]@{status=if($atInput){'ABORTED_RECOVERED_AT_INPUT'}else{'ABORTED_RECOVERED_FROM_PARTIAL'};completed_at_utc=[DateTime]::UtcNow.ToString('o')})|Out-Null
    }
}

$metaPath=Join-Path $project 'meta.md';$fundamentPath=Join-Path $project '00-fundament-projektu.md';foreach($p in @($metaPath,$fundamentPath)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "DURATION_POLICY_INPUT_MISSING: $p"}}
$preRecoveryMeta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $preRecoveryMeta | Out-Null
$recoveryLock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
try{Repair-SystemV7DurationTransactions -ProjectRoot $project}finally{Exit-SystemV7ProjectMetaLock -LockStream $recoveryLock}
$meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8;$fundament=Get-Content -LiteralPath $fundamentPath -Raw -Encoding UTF8;$origin=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
if(-not(Test-SystemV7NarrativeV2Revision -MetaText $meta)){throw 'DURATION_POLICY_ONLY_NARRATIVE_V2'}
$metaSha=(Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash;$fundamentSha=(Get-FileHash -LiteralPath $fundamentPath -Algorithm SHA256).Hash
$replaceBullet={param($text,$name,$value)$pattern="(?m)^- $([regex]::Escape($name)):\s*.*$";if([regex]::Matches($text,$pattern).Count -ne 1){throw "FUNDAMENT_FIELD_COUNT_INVALID: $name"};[regex]::Replace($text,$pattern,"- ${name}: $value",1)}
$newFundament=&$replaceBullet $fundament 'TARGET_DURATION_MODE' $Mode;$newFundament=&$replaceBullet $newFundament 'TARGET_MINUTES' ([string]$TargetMinutes)
$contextMeta=Set-SystemV7NarrativeMetaField -Text $meta -Name 'TARGET_DURATION_MODE' -Value $Mode;$contextMeta=Set-SystemV7NarrativeMetaField -Text $contextMeta -Name 'TARGET_MINUTES' -Value ([string]$TargetMinutes);$contextMeta=Set-SystemV7NarrativeMetaField -Text $contextMeta -Name 'DURATION_POLICY_RECEIPT_PATH' -Value 'BRAK';$contextMeta=Set-SystemV7NarrativeMetaField -Text $contextMeta -Name 'DURATION_POLICY_RECEIPT_SHA256' -Value 'BRAK'
$contextMetaSha=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7LfText -Text $contextMeta);$newFundamentSha=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7LfText -Text $newFundament)
$intent=[ordered]@{operation='SET_DURATION_POLICY';project_origin_sha256=$origin.Sha256;input_meta_sha256=$metaSha;input_fundament_sha256=$fundamentSha;mode=$Mode;target_minutes=$TargetMinutes;reason=$Reason.Trim();actor='DAWID'};$intentSha=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $intent)
$receiptCore=[ordered]@{schema='SYSTEM_V7_DURATION_POLICY_RECEIPT_V1';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;intent_sha256=$intentSha;project_origin_sha256=$origin.Sha256;input_meta_sha256=$metaSha;input_fundament_sha256=$fundamentSha;result_meta_context_sha256=$contextMetaSha;result_fundament_sha256=$newFundamentSha;mode=$Mode;target_minutes=$TargetMinutes;reason=$Reason.Trim();actor='DAWID';attestation_scope='AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY';created_at_utc=[DateTime]::UtcNow.ToString('o')};$receiptCore['binding_sha256']=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $receiptCore)
$receiptDir=Join-Path $project '_work\system\duration-policy';[IO.Directory]::CreateDirectory($receiptDir)|Out-Null;$receiptPath=Join-Path $receiptDir "duration-$intentSha.json";$receiptCreated=$false;if(-not(Test-Path -LiteralPath $receiptPath)){Write-SystemV7NarrativeCreateNewJson -Path $receiptPath -Value $receiptCore|Out-Null;$receiptCreated=$true};$receiptSha=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash;$receiptRelative=Get-SystemV7NarrativeRelativePath -Root $project -Path $receiptPath
$newMeta=Set-SystemV7NarrativeMetaField -Text $contextMeta -Name 'DURATION_POLICY_RECEIPT_PATH' -Value $receiptRelative;$newMeta=Set-SystemV7NarrativeMetaField -Text $newMeta -Name 'DURATION_POLICY_RECEIPT_SHA256' -Value $receiptSha
$newMetaSha=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7LfText -Text $newMeta)
$txRoot=Join-Path $project '.system-v7\duration-transactions';[IO.Directory]::CreateDirectory($txRoot)|Out-Null;$tx=Join-Path $txRoot ([guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($tx)|Out-Null
[IO.File]::WriteAllBytes((Join-Path $tx 'meta.before'),[IO.File]::ReadAllBytes($metaPath));[IO.File]::WriteAllBytes((Join-Path $tx 'fundament.before'),[IO.File]::ReadAllBytes($fundamentPath));Write-SystemV7NarrativeCreateNewJson -Path (Join-Path $tx 'PREPARED.json') -Value ([ordered]@{schema='SYSTEM_V7_DURATION_TRANSACTION_V2';input_meta_sha256=$metaSha;input_fundament_sha256=$fundamentSha;result_meta_sha256=$newMetaSha;result_fundament_sha256=$newFundamentSha;receipt_relative=$receiptRelative;receipt_sha256=$receiptSha;receipt_created=$receiptCreated;prepared_at_utc=[DateTime]::UtcNow.ToString('o')})|Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
try{
    if((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -cne $metaSha -or (Get-FileHash -LiteralPath $fundamentPath -Algorithm SHA256).Hash -cne $fundamentSha){throw 'DURATION_POLICY_COMPARE_AND_SWAP_CONFLICT'}
    Write-SystemV7NarrativeAtomicText -Path $fundamentPath -Text $newFundament|Out-Null
    try{Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text (ConvertTo-SystemV7LfText -Text $newMeta) -ExpectedCurrentSha256 $metaSha -HeldLockStream $lock}catch{[IO.File]::WriteAllBytes($fundamentPath,[IO.File]::ReadAllBytes((Join-Path $tx 'fundament.before')));throw}
    Write-SystemV7NarrativeCreateNewJson -Path (Join-Path $tx 'COMMITTED.json') -Value ([ordered]@{status='COMMITTED';completed_at_utc=[DateTime]::UtcNow.ToString('o')})|Out-Null
}catch{
    $currentMetaSha=(Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash;$currentFundamentSha=(Get-FileHash -LiteralPath $fundamentPath -Algorithm SHA256).Hash
    if($currentMetaSha -ceq $metaSha){
        if($currentFundamentSha -ne $fundamentSha){[IO.File]::WriteAllBytes($fundamentPath,[IO.File]::ReadAllBytes((Join-Path $tx 'fundament.before')))}
        if($receiptCreated -and (Test-Path -LiteralPath $receiptPath -PathType Leaf) -and (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash -ceq $receiptSha){[IO.File]::Delete($receiptPath)}
        if(-not(Test-Path -LiteralPath (Join-Path $tx 'ABORTED.json') -PathType Leaf)){Write-SystemV7NarrativeCreateNewJson -Path (Join-Path $tx 'ABORTED.json') -Value ([ordered]@{status='ABORTED_ROLLED_BACK';completed_at_utc=[DateTime]::UtcNow.ToString('o')})|Out-Null}
    }
    throw
}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
[pscustomobject]@{Status='DURATION_POLICY_UPDATED';Mode=$Mode;TargetMinutes=$TargetMinutes;ReceiptPath=$receiptPath;ReceiptSha256=$receiptSha;TransactionPath=$tx}
