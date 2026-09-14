[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$artifactRoot = Join-Path $repoRoot 'artifacts'
$null = New-Item -ItemType Directory -Path $artifactRoot -Force
Import-Module (Join-Path $repoRoot '.local/PowerShell/PSScriptAnalyzer/1.25.0/PSScriptAnalyzer.psd1') -ErrorAction Stop
$findings = @(
    foreach ($folder in @('system', 'panel', '.github/scripts')) {
        Invoke-ScriptAnalyzer -Path (Join-Path $repoRoot $folder) -Recurse |
            ForEach-Object {
                [pscustomobject]@{
                    file = [IO.Path]::GetRelativePath($repoRoot, $_.ScriptPath).Replace('\', '/')
                    line = $_.Line
                    severity = [string]$_.Severity
                    rule = $_.RuleName
                    message = $_.Message
                }
            }
    }
)
ConvertTo-Json -InputObject $findings -Depth 5 | Set-Content -LiteralPath (Join-Path $artifactRoot 'powershell.json') -Encoding utf8
$blocking = @($findings | Where-Object { $_.severity -in @('Error', 'ParseError') })
Write-Output "PSScriptAnalyzer: $($findings.Count) findings, $($blocking.Count) blocking; artifacts/powershell.json"
if ($env:GITHUB_ACTIONS -eq 'true') {
    foreach ($item in @($blocking + @($findings | Where-Object { $_.severity -notin @('Error', 'ParseError') })) | Select-Object -First 20) {
        $level = if ($item.severity -in @('Error', 'ParseError')) { 'error' } else { 'warning' }
        $file = $item.file.Replace('%', '%25').Replace(',', '%2C').Replace(':', '%3A')
        $message = ($item.rule + ': ' + $item.message).Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
        Write-Output "::$level file=$file,line=$($item.line)::$message"
    }
    if ($env:GITHUB_STEP_SUMMARY) {
        "### PowerShell / PSScriptAnalyzer`n`nFindings: **$($findings.Count)**; blocking: **$($blocking.Count)**. Full report: powershell.json.`n" |
            Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8
    }
}
if ($blocking.Count -gt 0) { exit 1 }
