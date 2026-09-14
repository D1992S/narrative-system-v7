[CmdletBinding()]
param([string]$PythonPath='python.exe')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Native-Python.ps1')
$checks=0
function Check([bool]$ok,[string]$code){if(-not $ok){throw "EFFICIENCY_TEST_FAILED: $code"};$script:checks++}
foreach($text in @('— Kto tam był? — zapytał oficer.','– Oficer nie wrócił.','Pokaż wzrost z 1,5 do 3,5 mln, zanim padnie nazwa obiektu.')){Check (Get-SystemV7PlainSpokenTextState -Text $text).Valid 'POLISH_PROSE'}
foreach($text in @('• Element listy','- Element listy','## Nagłówek')){Check (-not (Get-SystemV7PlainSpokenTextState -Text $text).Valid) 'TECHNICAL_MARKER_REJECTED'}
foreach($text in @('Pokaż, jak po I wojnie światowej i przed II wojną zniknęło archiwum.','Zamknij wątek sezonu 1947/48 bez rozstrzygania sporu.','Pokaż, że dr. Kowalski napisał raport w 1952 r. dla wojska.','Pokaż wzrost z 1,5 do 3,5 mln, zanim padnie nazwa obiektu.','Pokaż, jak Sodoma i Gomora trafiły do raportu raz i na zawsze.')){Check (Test-SystemV7SingleObligationText $text) 'POLISH_ATOMIC'}
foreach($text in @('Ujawnij nazwisko autora, a potem pokaż jego motyw i skutek oraz reakcję.','Pokaż raport; wyjaśnij motyw.','Pokaż autora i raport oraz konsekwencję.')){Check (-not (Test-SystemV7SingleObligationText $text)) 'MULTIPLE_OBLIGATIONS_REJECTED'}
$canonical=ConvertTo-SystemV7StrictCanonicalResponse -Text '{ "verdict": "FAIL", "schema": "CONTINUITY_ATTEST_RESULT_V1", "reason": "Zażółć gęślą jaźń" }'
Check ($canonical.Contains('Zażółć gęślą jaźń') -and $canonical.Contains('"FAIL"')) 'JSON_CONTENT_PRESERVED'
foreach($bad in @('{"schema":"CONTINUITY_ATTEST_RESULT_V1","x":{"a":1,"a":2}}','{"schema":"CONTINUITY_ATTEST_RESULT_V1","X":1,"x":2}','[]','not json')){
    $failed=$false;try{$null=ConvertTo-SystemV7StrictCanonicalResponse $bad}catch{$failed=$true};Check $failed 'AMBIGUOUS_JSON_REJECTED'
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('narrative-efficiency-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
try{
    $sample="W 1952 r. dr. Kowalski napisał, że obiekt miał 3,5 metra i ważył 1.000.000 ton. COVID-19, d'Artagnan – i tyle."
    $file=Join-Path $root 'sample.md';[IO.File]::WriteAllText($file,$sample,[Text.UTF8Encoding]::new($false))
    $legacy=& (Join-Path $PSScriptRoot 'Measure-Script.ps1') -ScriptPath $file
    Check ($legacy.WordCount -eq 19) 'LEGACY_MEASUREMENT_PRESERVED'
    [IO.File]::WriteAllText((Join-Path $root 'meta.md'),"WORKFLOW_REVISION: 2026-08-31_NARRATIVE_V2`nTARGET_DURATION_MODE: GUIDE`nTARGET_MINUTES: 10`nREAL_WPM: 130`n")
    $measure=& (Join-Path $PSScriptRoot 'Measure-Script.ps1') -ScriptPath $file
    Check ($measure.WordCount -eq 22) 'V2_MEASUREMENT_MATCHES_GATE'
    [IO.File]::WriteAllText($file,"FINAL_WORD_COUNT: 22`n---`n## NARRACJA DO NAGRANIA`n"+$sample)
    $measure=& (Join-Path $PSScriptRoot 'Measure-Script.ps1') -ScriptPath $file
    Check ($measure.WordCount -eq 22) 'V2_FINAL_EXTRACTION'
    $probe=Join-Path $root 'unicode probe.py'
    [IO.File]::WriteAllText($probe,"import sys,json`nprint(json.dumps({'text':'Zażółć ≈ Москва','arg':sys.argv[1]},ensure_ascii=False))`nprint('diagnostyka ≈',file=sys.stderr)`n",[Text.UTF8Encoding]::new($false))
    $oldEncoding=[Console]::OutputEncoding;$oldEnv=$env:PYTHONUTF8
    $run=Invoke-SystemV7PythonUtf8 -Python $PythonPath -Script $probe -Arguments @('ścieżka ze spacją')
    $data=$run.Stdout|ConvertFrom-Json
    Check ($run.ExitCode -eq 0 -and $data.text -ceq 'Zażółć ≈ Москва' -and $data.arg -ceq 'ścieżka ze spacją') 'UTF8_ARGUMENTS'
    Check ($run.Stderr.Contains('diagnostyka ≈') -and -not $run.Stdout.Contains('diagnostyka')) 'STDERR_SEPARATED'
    Check ([Console]::OutputEncoding.CodePage -eq $oldEncoding.CodePage -and $env:PYTHONUTF8 -ceq $oldEnv) 'PARENT_ENV_UNCHANGED'
}finally{
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not [IO.Path]::GetFullPath($root).StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'TEST_CLEANUP_OUTSIDE_TEMP'}
    [IO.Directory]::Delete($root,$true)
}
[pscustomobject]@{Verdict='PASS';Checks=$checks}
