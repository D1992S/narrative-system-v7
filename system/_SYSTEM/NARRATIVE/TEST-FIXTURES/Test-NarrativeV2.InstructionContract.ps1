param([Parameter(Mandatory)][string]$SystemRoot)
$ErrorActionPreference='Stop'
$systemRoot=[IO.Path]::GetFullPath($SystemRoot)
$tools=Join-Path $systemRoot 'tools'
. (Join-Path $tools 'Narrative-V2.ps1')

$agentsPath=Join-Path $systemRoot 'AGENTS.md'
$contractPath=Join-Path $systemRoot '_SYSTEM\NARRATIVE\NARRATIVE-CONTRACT-V2.md'
$rulesPath=Join-Path $systemRoot '_SYSTEM\NARRATIVE\K3-RULES-CORE.md'
$manifestPath=Join-Path $systemRoot '_SYSTEM\NARRATIVE\NARRATIVE-INSTRUCTION-MANIFEST.json'
$agentsBytes=[IO.File]::ReadAllBytes($agentsPath);$contractBytes=[IO.File]::ReadAllBytes($contractPath);$rulesBytes=[IO.File]::ReadAllBytes($rulesPath);$manifestBytes=[IO.File]::ReadAllBytes($manifestPath)
$agentsHash=(Get-FileHash -LiteralPath $agentsPath -Algorithm SHA256).Hash;$contractHash=(Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash
$rulesHash=(Get-FileHash -LiteralPath $rulesPath -Algorithm SHA256).Hash;$manifestHash=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
$utf8=[Text.UTF8Encoding]::new($false,$true)
$baseline=Get-SystemV7NarrativeInstructionContractState -SystemRoot $systemRoot
$markerRejected=$false;$routeRejected=$false;$statusRejected=$false;$controlledFileRejected=$false;$manifestHashRejected=$false;$manifestAllowlistRejected=$false
try{
    $agents=$utf8.GetString($agentsBytes)
    $mutant=$agents.Replace('NARRATIVE_V2_CONTRACT: 2026-08-31_NARRATIVE_V2','NARRATIVE_V2_CONTRACT: BROKEN')
    if($mutant -ceq $agents){throw 'INSTRUCTION_MARKER_TAMPER_PATTERN_MISSING'}
    [IO.File]::WriteAllText($agentsPath,$mutant,[Text.UTF8Encoding]::new($false))
    $state=Get-SystemV7NarrativeInstructionContractState -SystemRoot $systemRoot
    $markerRejected=(-not $state.Valid) -and @($state.Errors|Where-Object{$_ -like 'INSTRUCTION_AGENTS_CONTRACT_MARKER_INVALID:*'}).Count -eq 1
    [IO.File]::WriteAllBytes($agentsPath,$agentsBytes)

    $mutant=$agents.Replace('_SYSTEM/NARRATIVE/NARRATIVE-CONTRACT-V2.md','_SYSTEM/NARRATIVE/BROKEN-CONTRACT.md')
    if($mutant -ceq $agents){throw 'INSTRUCTION_ROUTE_TAMPER_PATTERN_MISSING'}
    [IO.File]::WriteAllText($agentsPath,$mutant,[Text.UTF8Encoding]::new($false))
    $state=Get-SystemV7NarrativeInstructionContractState -SystemRoot $systemRoot
    $routeRejected=(-not $state.Valid) -and @($state.Errors|Where-Object{$_ -ceq 'INSTRUCTION_AGENTS_ROUTE_MISSING'}).Count -eq 1
    [IO.File]::WriteAllBytes($agentsPath,$agentsBytes)

    $contract=$utf8.GetString($contractBytes)
    $mutant=$contract.Replace('NARRATIVE_V2_STATUS: PILOT_ONLY','NARRATIVE_V2_STATUS: DISABLED')
    if($mutant -ceq $contract){throw 'INSTRUCTION_STATUS_TAMPER_PATTERN_MISSING'}
    [IO.File]::WriteAllText($contractPath,$mutant,[Text.UTF8Encoding]::new($false))
    $state=Get-SystemV7NarrativeInstructionContractState -SystemRoot $systemRoot
    $statusRejected=(-not $state.Valid) -and @($state.Errors|Where-Object{$_ -like 'INSTRUCTION_NARRATIVE_CONTRACT_STATUS_MARKER_INVALID:*'}).Count -eq 1
    [IO.File]::WriteAllBytes($contractPath,$contractBytes)

    $rules=$utf8.GetString($rulesBytes)
    [IO.File]::WriteAllText($rulesPath,$rules+"`nNIEAUTORYZOWANY_DRIFT",[Text.UTF8Encoding]::new($false))
    $state=Get-SystemV7NarrativeInstructionContractState -SystemRoot $systemRoot
    $controlledFileRejected=(-not $state.Valid) -and @($state.Errors|Where-Object{$_ -ceq 'INSTRUCTION_FILE_SHA_MISMATCH: _SYSTEM/NARRATIVE/K3-RULES-CORE.md'}).Count -eq 1
    [IO.File]::WriteAllBytes($rulesPath,$rulesBytes)

    $manifest=$utf8.GetString($manifestBytes)|ConvertFrom-Json -DateKind String -Depth 64
    $target=@($manifest.entries|Where-Object{[string]$_.path -ceq '_SYSTEM/NARRATIVE/K3-RULES-CORE.md'})
    if($target.Count -ne 1){throw 'INSTRUCTION_MANIFEST_TAMPER_TARGET_MISSING'}
    $target[0].sha256=('0'*64)
    [IO.File]::WriteAllText($manifestPath,(ConvertTo-SystemV7CanonicalJson -Value $manifest),[Text.UTF8Encoding]::new($false))
    $state=Get-SystemV7NarrativeInstructionContractState -SystemRoot $systemRoot
    $manifestHashRejected=(-not $state.Valid) -and @($state.Errors|Where-Object{$_ -ceq 'INSTRUCTION_FILE_SHA_MISMATCH: _SYSTEM/NARRATIVE/K3-RULES-CORE.md'}).Count -eq 1
    [IO.File]::WriteAllBytes($manifestPath,$manifestBytes)

    $manifest=$utf8.GetString($manifestBytes)|ConvertFrom-Json -DateKind String -Depth 64
    $manifest.entries[0].path='UNLISTED-INSTRUCTION.md'
    [IO.File]::WriteAllText($manifestPath,(ConvertTo-SystemV7CanonicalJson -Value $manifest),[Text.UTF8Encoding]::new($false))
    $state=Get-SystemV7NarrativeInstructionContractState -SystemRoot $systemRoot
    $manifestAllowlistRejected=(-not $state.Valid) -and @($state.Errors|Where-Object{$_ -like 'INSTRUCTION_MANIFEST_ALLOWLIST_OR_ORDER_INVALID:*' -or $_ -ceq 'INSTRUCTION_MANIFEST_ALLOWLIST_INVALID'}).Count -gt 0
}finally{
    [IO.File]::WriteAllBytes($agentsPath,$agentsBytes);[IO.File]::WriteAllBytes($contractPath,$contractBytes);[IO.File]::WriteAllBytes($rulesPath,$rulesBytes);[IO.File]::WriteAllBytes($manifestPath,$manifestBytes)
}
$restored=Get-SystemV7NarrativeInstructionContractState -SystemRoot $systemRoot
[pscustomobject]@{
    BaselineValid=[bool]$baseline.Valid
    MarkerRejected=$markerRejected
    RouteRejected=$routeRejected
    StatusRejected=$statusRejected
    ControlledFileRejected=$controlledFileRejected
    ManifestHashRejected=$manifestHashRejected
    ManifestAllowlistRejected=$manifestAllowlistRejected
    ExactRestore=([bool]$restored.Valid -and (Get-FileHash -LiteralPath $agentsPath -Algorithm SHA256).Hash -ceq $agentsHash -and (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash -ceq $contractHash -and (Get-FileHash -LiteralPath $rulesPath -Algorithm SHA256).Hash -ceq $rulesHash -and (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ceq $manifestHash)
}
