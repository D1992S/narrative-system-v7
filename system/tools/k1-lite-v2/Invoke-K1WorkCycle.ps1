[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Prepare','Accept','Recover','Status','PreviewBatch')][string]$Action,
    [Parameter(Mandatory)][string]$ProjectDirectory,
    [Parameter(Mandatory)][string]$RunDirectory,
    [string]$TaskId,
    [string]$ResultPath,
    [string[]]$ResultPaths,
    [string]$Model = 'UNSPECIFIED',
    [string]$Effort = 'medium',
    [string]$PythonPath = 'python.exe'
)
$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$project = [IO.Path]::GetFullPath($ProjectDirectory)
foreach ($candidate in @($project,(Join-Path $project '.system-v7'))) {
    $cursor = $candidate
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'WORK_REPARSE_POINT_BLOCKED'
        }
        $parent = [IO.Directory]::GetParent($cursor)
        $cursor = if ($parent) { $parent.FullName } else { $null }
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $project 'sources') -PathType Container)) { throw 'PROJECT_SOURCES_NOT_FOUND' }
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Integrity-Receipts.ps1')
$arguments = @('-B',(Join-Path $PSScriptRoot 'work_cycle.py'),'--action',$Action,'--root',$project,
    '--run',[IO.Path]::GetFullPath($RunDirectory),'--model',$Model,'--effort',$Effort)
if ($TaskId) { $arguments += @('--task-id',$TaskId) }
if ($ResultPath) { $arguments += @('--response',[IO.Path]::GetFullPath($ResultPath)) }
foreach ($item in $ResultPaths) { $arguments += @('--result',[IO.Path]::GetFullPath($item)) }
$projectLock = $null
try {
    if ($Action -ne 'Status') { $projectLock = Enter-SystemV7ProjectMetaLock -ProjectPath $project }
    $output = & $PythonPath @arguments
    if ($LASTEXITCODE -ne 0) { throw ('K1_WORK_CYCLE_FAILED: ' + ($output -join "`n")) }
    $output
} finally {
    if ($null -ne $projectLock) { $projectLock.Dispose() }
}
