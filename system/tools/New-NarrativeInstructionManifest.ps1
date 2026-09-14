[CmdletBinding()]
param(
    [string]$SystemRoot=(Split-Path -Parent $PSScriptRoot),
    [switch]$Write
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($SystemRoot)
. (Join-Path $root 'tools\Narrative-V2.ps1')
$entries=[Collections.Generic.List[object]]::new()
foreach($relative in @(Get-SystemV7NarrativeInstructionRelativePaths)){
    $state=Get-SystemV7NarrativeInstructionPathState -SystemRoot $root -RelativePath $relative
    if(-not $state.Valid){throw "INSTRUCTION_PATH_INVALID: $($state.Errors -join '; ')"}
    if(-not(Test-Path -LiteralPath $state.FullPath -PathType Leaf)){throw "INSTRUCTION_FILE_MISSING: $relative"}
    $bytes=[IO.File]::ReadAllBytes($state.FullPath)
    if($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF){throw "INSTRUCTION_FILE_UTF8_BOM_FORBIDDEN: $relative"}
    $null=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
    $entries.Add([ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath $state.FullPath -Algorithm SHA256).Hash})
}
$value=[ordered]@{
    schema='NARRATIVE_INSTRUCTION_MANIFEST_V1'
    workflow_revision=$script:SystemV7NarrativeWorkflowRevision
    status='PILOT_ONLY'
    entries=@($entries)
}
$text=ConvertTo-SystemV7CanonicalJson -Value $value
$path=Join-Path $root '_SYSTEM\NARRATIVE\NARRATIVE-INSTRUCTION-MANIFEST.json'
if($Write){
    Write-SystemV7NarrativeAtomicText -Path $path -Text $text|Out-Null
    $state=Get-SystemV7NarrativeInstructionContractState -SystemRoot $root
    if(-not $state.Valid){throw "NARRATIVE_INSTRUCTION_MANIFEST_POSTWRITE_INVALID: $($state.Errors -join '; ')"}
    [pscustomobject]@{Status='NARRATIVE_INSTRUCTION_MANIFEST_WRITTEN';Path=$path;EntryCount=$entries.Count;Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
}else{
    [pscustomobject]@{Status='PREVIEW';Path=$path;EntryCount=$entries.Count;CanonicalJson=$text}
}
