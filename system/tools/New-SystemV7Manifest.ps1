[CmdletBinding()]
param(
    [string]$SystemRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($SystemRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "SYSTEM_ROOT_MISSING: $root"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $root '_SYSTEM\NARRATIVE\_IMPLEMENTATION\BASELINE-MANIFEST.json'
}
$target = [IO.Path]::GetFullPath($OutputPath)
$targetDir = Split-Path -Parent $target
[IO.Directory]::CreateDirectory($targetDir) | Out-Null

$excludedSegments = @('\.git\', '\_test-run\', '\__pycache__\')
$entries = foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Sort-Object FullName)) {
    $normalized = $file.FullName.Replace('/', '\')
    if ($excludedSegments | Where-Object { $normalized.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 }) { continue }
    if ($file.FullName.Equals($target, [StringComparison]::OrdinalIgnoreCase)) { continue }
    [ordered]@{
        path = $file.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        bytes = [int64]$file.Length
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
}
$canonicalLines = @($entries | ForEach-Object { '{0}|{1}|{2}' -f $_.path, $_.bytes, $_.sha256 })
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $aggregate = [Convert]::ToHexString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes(($canonicalLines -join "`n"))))
} finally {
    $sha.Dispose()
}
$totalBytes = [int64]0
foreach ($entry in @($entries)) { $totalBytes += [int64]$entry['bytes'] }
$record = [ordered]@{
    schema = 'SYSTEM_V7_BASELINE_MANIFEST_V1'
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
    system_root = $root
    file_count = @($entries).Count
    total_bytes = $totalBytes
    aggregate_sha256 = $aggregate
    files = @($entries)
}
$json = ($record | ConvertTo-Json -Depth 5) + "`n"
$temp = Join-Path $targetDir ('.manifest-' + [guid]::NewGuid().ToString('N') + '.tmp')
[IO.File]::WriteAllText($temp, $json, [Text.UTF8Encoding]::new($false))
try {
    if (Test-Path -LiteralPath $target) {
        $backup = Join-Path $targetDir ('.manifest-backup-' + [guid]::NewGuid().ToString('N') + '.tmp')
        try { [IO.File]::Replace($temp, $target, $backup, $true) }
        finally { if (Test-Path -LiteralPath $backup -PathType Leaf) { [IO.File]::Delete($backup) } }
    } else {
        [IO.File]::Move($temp, $target)
    }
} finally {
    if (Test-Path -LiteralPath $temp -PathType Leaf) { [IO.File]::Delete($temp) }
}

[pscustomobject]@{
    Path = $target
    FileCount = $record.file_count
    TotalBytes = $record.total_bytes
    AggregateSha256 = $aggregate
}
