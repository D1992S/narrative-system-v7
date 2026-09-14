[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][string[]]$RunDirectories,
    [Parameter(Mandatory)][string[]]$ExpectedLedgerSha256s,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$PythonPath = 'python.exe',
    [IO.FileStream]$InternalHeldProjectLock
)

$ErrorActionPreference = 'Stop'
if ($RunDirectories.Count -lt 1 -or $RunDirectories.Count -ne $ExpectedLedgerSha256s.Count) { throw 'RUN_AND_HASH_COUNT_MISMATCH' }
$project = [IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
Assert-SystemV7NarrativeInstructionContractIfV2 -ProjectPath $project | Out-Null
$metaPath = Join-Path $project 'meta.md'
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "META_MISSING: $metaPath" }
$metaForAuthorization = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$originAuthorization = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $metaForAuthorization
if ($null -ne $InternalHeldProjectLock) {
    $callerPathForLock = if ($MyInvocation.ScriptName) { [IO.Path]::GetFullPath($MyInvocation.ScriptName) } else { '' }
    $allowedCaller = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Compile-K1LiteV2.ps1'))
    if (-not $callerPathForLock.Equals($allowedCaller, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'INTERNAL_HELD_PROJECT_LOCK_UNAUTHORIZED'
    }
}
$ownsProjectLock = $null -eq $InternalHeldProjectLock
$projectLock = if ($ownsProjectLock) { Enter-SystemV7ProjectMetaLock -ProjectPath $project } else { $InternalHeldProjectLock }
try {
$metaForAuthorization = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$originAuthorization = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $metaForAuthorization
$root = [IO.Path]::GetFullPath((Join-Path $project '_work\K1\k1-lite-v2'))
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (-not $output.StartsWith($root.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'OUTPUT_OUTSIDE_K1_RUN_ROOT' }
if (Test-Path -LiteralPath $output) { throw 'OUTPUT_EXISTS' }
$compiler = Join-Path $PSScriptRoot 'Compile-K1LiteV2.ps1'
$validator = Join-Path $PSScriptRoot 'Validate-EvidenceBase.ps1'

function Parse-Row([string]$Line) {
    $c=@($Line -split '(?<!\\)\|'); if($c.Count -lt 12){throw 'SOURCE_ROW_INVALID'}
    [pscustomobject]@{Cells=$c; Id=$c[1].Trim().TrimStart('#'); Hash=$c[8].Trim().ToUpperInvariant()}
}
function Parse-Cards([string]$Text) {
    $r=[Collections.Generic.List[object]]::new()
    foreach($m in [regex]::Matches($Text,'(?ms)^### #P-(?<id>\d{3,})\r?\n\r?\n(?<body>.*?)(?=^### #P-|^## 4\.)')){
        $body=$m.Groups['body'].Value.TrimEnd(); $sid=[regex]::Match($body,'(?m)^ŹRÓDŁO_ID:\s*#(?<id>S-\d{3,})\s*$').Groups['id'].Value
        $loc=[regex]::Match($body,'(?m)^LOKALIZACJA:\s*(?<v>.+?)\s*$').Groups['v'].Value.Trim(); $txt=[regex]::Match($body,'(?m)^TREŚĆ:\s*(?<v>.+?)\s*$').Groups['v'].Value.Trim()
        if(-not $sid -or -not $loc -or -not $txt){throw 'CARD_INVALID'}
        $r.Add([pscustomobject]@{OldId=[int]$m.Groups['id'].Value; Source=$sid; Locator=$loc; Content=$txt; Body=$body})
    }; @($r)
}
function Get-RunCreatedUtcDateFromJson([string]$Json) {
    $document=$null
    try{
        $document=[Text.Json.JsonDocument]::Parse($Json)
        $createdAt=[string]$document.RootElement.GetProperty('created_at').GetString()
    }catch{throw 'RUN_CREATED_AT_INVALID'}finally{if($null -ne $document){$document.Dispose()}}
    $formats=[string[]]@("yyyy-MM-dd'T'HH:mm:ss'Z'","yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'")
    $styles=[Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    $parsed=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParseExact($createdAt,$formats,[Globalization.CultureInfo]::InvariantCulture,$styles,[ref]$parsed)){throw 'RUN_CREATED_AT_INVALID'}
    $parsed.ToString('yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
}

$documents=[Collections.Generic.List[object]]::new(); $coveredFiles=@{}; $coverageOwners=@{}; $allLedgerLines=[Collections.Generic.List[string]]::new()
for($i=0;$i -lt $RunDirectories.Count;$i++){
    $run=[IO.Path]::GetFullPath($RunDirectories[$i]); if(-not $run.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'RUN_OUTSIDE_K1_RUN_ROOT'}
    $hash=$ExpectedLedgerSha256s[$i].ToUpperInvariant(); if($hash -notmatch '^[A-F0-9]{64}$'){throw 'EXPECTED_LEDGER_SHA_INVALID'}
    $ledger=Join-Path $run 'ledger.jsonl'; if((Get-FileHash -LiteralPath $ledger -Algorithm SHA256).Hash -ne $hash){throw 'LEDGER_SHA_MISMATCH'}
    $raw=Join-Path $output ("_run-{0:D3}" -f ($i+1))
    $preview=& $compiler -Action Preview -ProjectPath $project -RunDirectory $run -ExpectedLedgerSha256 $hash -OutputDirectory $raw -PythonPath $PythonPath -InternalAllowCorpusSubset -InternalHeldProjectLock $projectLock
    $text=Get-Content -LiteralPath $preview.PreviewPath -Raw -Encoding UTF8; $lines=@($text -split '\r?\n'); $rows=[Collections.Generic.List[object]]::new()
    foreach($line in $lines){if($line -match '^\| #S-\d{3,}\s+\|'){$rows.Add((Parse-Row $line))}}
    $runJsonText=Get-Content -LiteralPath (Join-Path $run 'run.json') -Raw -Encoding UTF8
    $runData=$runJsonText|ConvertFrom-Json -DateKind String
    $runDate=Get-RunCreatedUtcDateFromJson $runJsonText
    if([string]$runData.engine_version -ne '2.1.0'){throw "RUN_ENGINE_VERSION_UNSUPPORTED: $($runData.engine_version)"}
    foreach($rel in @([string]$runData.source_relative,[string]$runData.pdf_relative)){if($rel){$fp=[IO.Path]::GetFullPath((Join-Path $project $rel)); if(Test-Path -LiteralPath $fp){$key=$fp.ToLowerInvariant();if($coverageOwners.ContainsKey($key)){throw "CORPUS_FILE_COVERED_BY_MULTIPLE_RUNS: $fp; runs=$($coverageOwners[$key]);$run"};$coverageOwners[$key]=$run;$coveredFiles[$key]=(Get-FileHash -LiteralPath $fp -Algorithm SHA256).Hash}}}
    foreach($line in Get-Content -LiteralPath $ledger -Encoding UTF8){if($line.Trim()){$allLedgerLines.Add($line)}}
    $documents.Add([pscustomobject]@{Text=$text; Lines=$lines; Rows=@($rows); Cards=@(Parse-Cards $text); Run=$run; RunData=$runData; RunDate=$runDate; LedgerSha256=$hash})
}

$sourcesRoot=[IO.Path]::GetFullPath((Join-Path $project 'sources'));$supportedExtensions=@('.pdf','.md','.txt','.srt','.vtt')
$nestedSupported=@(Get-ChildItem -LiteralPath $sourcesRoot -Recurse -File|Where-Object{$_.DirectoryName -ne $sourcesRoot -and $_.FullName -notmatch '\\_oryginaly(?:\\|$)' -and $_.Extension.ToLowerInvariant() -in $supportedExtensions})
if($nestedSupported.Count){throw "SUPPORTED_SOURCE_IN_SUBDIRECTORY: $($nestedSupported.FullName -join '; ')"}
$active=@(Get-ChildItem -LiteralPath $sourcesRoot -File|Where-Object{$_.Extension.ToLowerInvariant() -in $supportedExtensions})
$missing=@($active|Where-Object{-not $coveredFiles.ContainsKey($_.FullName.ToLowerInvariant()) -or $coveredFiles[$_.FullName.ToLowerInvariant()] -ne (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash})
if($missing.Count){throw "CORPUS_UNANALYSED_FILES: $($missing.FullName -join '; ')"}

$master=@{}; foreach($doc in $documents){foreach($row in $doc.Rows){$masterKey=$row.Cells[2].Trim().ToLowerInvariant()+'|'+$row.Hash;if(-not $master.ContainsKey($masterKey)){$master[$masterKey]=[pscustomobject]@{Cells=$row.Cells.Clone(); Hash=$row.Hash; Key=$masterKey; Id=''; Cards=[Collections.Generic.List[string]]::new()}}
    if($row.Cells[6].Trim() -eq 'RDZEŃ'){$master[$masterKey].Cells[5]=$row.Cells[5];$master[$masterKey].Cells[6]=' RDZEŃ ';$master[$masterKey].Cells[7]=$row.Cells[7]}}}
$ordered=@($master.Values|Sort-Object{$_.Cells[2]}); for($i=0;$i -lt $ordered.Count;$i++){$ordered[$i].Id='S-{0:D3}' -f ($i+1);$ordered[$i].Cells[1]=" #$($ordered[$i].Id) ";$ordered[$i].Cells[9]=' — '}

$global=[Collections.Generic.List[object]]::new(); $seen=@{}; $cardMap=@{}
for($di=0;$di -lt $documents.Count;$di++){
    $doc=$documents[$di]; $keyByOld=@{}; foreach($row in $doc.Rows){$keyByOld[$row.Id]=$row.Cells[2].Trim().ToLowerInvariant()+'|'+$row.Hash}
    foreach($card in $doc.Cards){$target=$master[$keyByOld[$card.Source]]; if(-not $target){throw 'CARD_SOURCE_HASH_MISSING'}; $key="$($target.Key)|$($card.Locator)|$($card.Content)"
        if($seen.ContainsKey($key)){$newId=$seen[$key]}else{$newId=$global.Count+1;$seen[$key]=$newId;$body=[regex]::Replace($card.Body,'(?m)^ŹRÓDŁO_ID:\s*#S-\d{3,}\s*$',"ŹRÓDŁO_ID: #$($target.Id)");$global.Add([pscustomobject]@{Id=$newId;Source=$target.Id;Body=$body});$target.Cards.Add(('#P-{0:D3}' -f $newId))}
        $cardMap["$di|$($card.OldId)"]=$newId
    }
}
foreach($row in $ordered){if($row.Cards.Count){$row.Cells[9]=" $($row.Cards -join ', ') "}}

$runDates=[Collections.Generic.List[string]]::new()
foreach($doc in $documents){
    $runDates.Add([string]$doc.RunDate)
}
$corpusDate=@($runDates|Sort-Object -Descending)[0]

$coverage=@{}; for($di=0;$di -lt $documents.Count;$di++){foreach($line in $documents[$di].Lines){$m=[regex]::Match($line,'^\|\s*(Q-\d{3,})\s*\|\s*POKRYTY\s*\|\s*([^|]+)\|');if($m.Success){$goal=$m.Groups[1].Value;if(-not $coverage.ContainsKey($goal)){$coverage[$goal]=[Collections.Generic.List[string]]::new()};foreach($pm in [regex]::Matches($m.Groups[2].Value,'#P-(\d{3,})')){$id=$cardMap["$di|$([int]$pm.Groups[1].Value)"];if($id){$v='#P-{0:D3}' -f $id;if(-not $coverage[$goal].Contains($v)){$coverage[$goal].Add($v)}}}}}}

[IO.Directory]::CreateDirectory($output)|Out-Null
$combinedLedger=Join-Path $output 'ledger.jsonl'; [IO.File]::WriteAllText($combinedLedger,(($allLedgerLines -join "`n")+"`n"),[Text.UTF8Encoding]::new($false));$combinedHash=(Get-FileHash -LiteralPath $combinedLedger -Algorithm SHA256).Hash
$corpusId='corpus-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$aggregate=[ordered]@{
    run_id=$corpusId;run_type='CORPUS_COMPILE';engine_version='2.1.0';locator_policy='MIXED_V1'
    source_runs=@($documents|ForEach-Object{$_.RunData.run_id})
    source_run_relatives=@($documents|ForEach-Object{[IO.Path]::GetRelativePath($project,$_.Run).Replace('\','/')})
    source_ledger_sha256s=@($documents|ForEach-Object{$_.LedgerSha256})
    ledger_sha256=$combinedHash
}
[IO.File]::WriteAllText((Join-Path $output 'run.json'),(($aggregate|ConvertTo-Json -Depth 5)+"`n"),[Text.UTF8Encoding]::new($false))

$base=$documents[0].Lines;$first=-1;$cardHeader=-1;$change=-1;for($i=0;$i -lt $base.Count;$i++){if($first -lt 0 -and $base[$i]-match '^\| #S-\d{3,}\s+\|'){$first=$i};if($base[$i]-eq '## 3. Karty dowodowe'){$cardHeader=$i};if($base[$i]-eq '## 4. Changelog'){$change=$i}}
if($first -lt 0 -or $cardHeader -lt 0 -or $change -lt 0){throw 'PREVIEW_SECTIONS_INVALID'}
$out=[Collections.Generic.List[string]]::new();foreach($line in $base[0..($first-1)]){if($line-match '^K1_EXPORT_PATH:'){$out.Add("K1_EXPORT_PATH: $([IO.Path]::GetRelativePath($project,$combinedLedger).Replace('\','/'))")}elseif($line-match '^K1_EXPORT_SHA256:'){$out.Add("K1_EXPORT_SHA256: $combinedHash")}elseif($line-match '^DATA_ODCIĘCIA:'){$out.Add("DATA_ODCIĘCIA: $corpusDate")}elseif($line-match '^\|\s*(Q-\d{3,})\s*\|'){$goal=$Matches[1];if($coverage.ContainsKey($goal)){$out.Add("| $goal | POKRYTY | $($coverage[$goal] -join ', ') | Pokrycie zagregowane ze zweryfikowanych runów. |") }else{$out.Add($line)}}else{$out.Add($line)}}
foreach($row in $ordered){$out.Add(($row.Cells -join '|'))};$out.Add('');$out.Add('## 3. Karty dowodowe');$out.Add('')
foreach($card in $global){$out.Add(('### #P-{0:D3}' -f $card.Id));$out.Add('');foreach($line in @($card.Body -split '\r?\n')){$out.Add($line)};$out.Add('')}
$out.Add('## 4. Changelog');$out.Add('');$out.Add("- $corpusDate — kompilacja korpusu z $($documents.Count) runów; ledger $combinedHash.")
$previewPath=Join-Path $output "K1-COMPILED-$corpusId.md";[IO.File]::WriteAllText($previewPath,(($out -join "`r`n")+"`r`n"),[Text.UTF8Encoding]::new($false))
$check=& $validator -ProjectPath $project -EvidencePath $previewPath -PendingReview -NoExit;if($check.Errors -gt 0 -or -not $check.ReadyForImport){throw "CORPUS_PREVIEW_INVALID: $($check.ErrorDetails -join '; ')"}
[pscustomobject]@{Status='CORPUS_PREVIEW_READY';RunDirectory=$output;LedgerSha256=$combinedHash;PreviewPath=$previewPath;PreviewSha256=(Get-FileHash -LiteralPath $previewPath -Algorithm SHA256).Hash;Runs=$documents.Count;Cards=$global.Count;Sources=$ordered.Count}
} finally {
    if ($ownsProjectLock) { Exit-SystemV7ProjectMetaLock -LockStream $projectLock }
}
