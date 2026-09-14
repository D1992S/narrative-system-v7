[CmdletBinding()]
param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][ValidatePattern('^[A-Z0-9][A-Z0-9._-]{7,80}$')][string]$RunId,[Parameter(Mandatory)][string]$RawPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
$project=[IO.Path]::GetFullPath($ProjectPath)
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
try {
    $run=Join-Path $project "_work/narrative-runs/$RunId"
    $raw=[IO.Path]::GetFullPath($RawPath)
    $null=Get-SystemV7NarrativeRelativePath -Root $run -Path $raw
    $null=Assert-SystemV7PathNoReparse -Path $raw -ContainmentRoot $project
    $manifest=Join-Path $run 'input-manifest.json'
    $bundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $manifest -RequireLiveSource
    if(-not $bundle.Valid -or [string]$bundle.Data.run_type -cne 'CONTINUITY_ATTEST'){throw 'NORMALIZATION_INPUT_BUNDLE_INVALID'}
    $bytes=[IO.File]::ReadAllBytes($raw);$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
    $canonical=ConvertTo-SystemV7StrictCanonicalResponse -Text $text
    $output=Get-SystemV7NarrativeExpectedRunOutputPath -ProjectPath $project -BundleData $bundle.Data
    if($raw.Equals($output,[StringComparison]::OrdinalIgnoreCase)){throw 'RAW_AND_CANONICAL_PATH_MUST_DIFFER'}
    $binding=[ordered]@{schema='LOCAL_RESPONSE_NORMALIZATION_V1';raw_relative=(Get-SystemV7NarrativeRelativePath -Root $project -Path $raw);raw_sha256=(Get-Sha256HexFromBytes -Bytes $bytes);canonical_sha256=(Get-SystemV7NarrativeSha256Text -Text $canonical);input_manifest_sha256=$bundle.FileSha256}
    $publish={param($path,$content)
        $null=Assert-SystemV7PathNoReparse -Path $path -ContainmentRoot $project
        if(Test-Path -LiteralPath $path){if([IO.File]::ReadAllText($path) -cne $content){throw 'NORMALIZATION_OUTPUT_EXISTS_DIFFERENT'};return}
        $temporary=Join-Path $run ('.normalize-'+[guid]::NewGuid().ToString('N')+'.tmp')
        try{[IO.File]::WriteAllText($temporary,$content,[Text.UTF8Encoding]::new($false));[IO.File]::Move($temporary,$path)}finally{if(Test-Path -LiteralPath $temporary){[IO.File]::Delete($temporary)}}
    }
    if((Get-FileHash -LiteralPath $raw).Hash -cne $binding.raw_sha256 -or (Get-FileHash -LiteralPath $manifest).Hash -cne $bundle.FileSha256){throw 'NORMALIZATION_INPUT_CHANGED'}
    &$publish (Join-Path $run 'normalization.json') (ConvertTo-SystemV7CanonicalJson -Value $binding)
    &$publish $output $canonical
    [pscustomobject]@{Status='FORMAT_NORMALIZED_REQUIRES_VALIDATION';OutputPath=$output;RawPath=$raw;ModelCallRequired=$false}
}finally{$lock.Dispose()}
