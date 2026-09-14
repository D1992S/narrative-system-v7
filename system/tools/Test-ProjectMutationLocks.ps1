[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$newProject = Join-Path $PSScriptRoot 'New-Project.ps1'
$inventory = Join-Path $PSScriptRoot 'Build-SourceInventory.ps1'
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('system-v7-project-lock-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
try {
    $created = & $newProject -NarrativeV2Pilot:$false -ProjectName 'project-lock-test' -DestinationRoot $testRoot
    $project = [string]$created.ProjectPath
    [IO.File]::WriteAllText(
        (Join-Path $project 'sources\source.md'),
        'Kontrolowana treść źródłowa do testu wspólnej blokady projektu.',
        [Text.UTF8Encoding]::new($false)
    )

    $heldLock = Enter-SystemV7ProjectMetaLock -ProjectPath $project
    try {
        $preview = & $inventory -ProjectPath $project
        if ($preview.Mode -ne 'PREVIEW') { throw 'READ_ONLY_PREVIEW_DID_NOT_RUN_UNDER_HELD_LOCK' }

        $stdout = Join-Path $testRoot 'contended.stdout.txt'
        $stderr = Join-Path $testRoot 'contended.stderr.txt'
        $pwsh = Join-Path $PSHOME 'pwsh.exe'
        $process = Start-Process -FilePath $pwsh -ArgumentList @(
            '-NoLogo','-NoProfile','-NonInteractive','-File',('"' + $inventory + '"'),
            '-ProjectPath',('"' + $project + '"'),'-Write'
        ) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $combined = ((Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue) + "`n" +
            (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue))
        if ($process.ExitCode -eq 0 -or $combined -notmatch 'PROJECT_META_LOCK_TIMEOUT') {
            throw "CONTENDED_MUTATOR_DID_NOT_FAIL_CLOSED: exit=$($process.ExitCode) output=$combined"
        }
        if (Test-Path -LiteralPath (Join-Path $project '_work\K1\source-inventory.generated.md')) {
            throw 'CONTENDED_MUTATOR_WROTE_ARTIFACT'
        }
    } finally {
        Exit-SystemV7ProjectMetaLock -LockStream $heldLock
    }

    $written = & $inventory -ProjectPath $project -Write
    if ($written.Mode -ne 'WRITE' -or -not (Test-Path -LiteralPath $written.OutputPath -PathType Leaf)) {
        throw 'MUTATOR_DID_NOT_WRITE_AFTER_LOCK_RELEASE'
    }

    [pscustomobject]@{
        Status = 'PROJECT_MUTATION_LOCK_TEST_PASS'
        ReadOnlyPreviewWhileLocked = 'PASS'
        ConcurrentWriterFailClosed = 'PASS'
        WriteAfterRelease = 'PASS'
    }
} finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        [IO.Directory]::Delete($testRoot, $true)
    }
}
