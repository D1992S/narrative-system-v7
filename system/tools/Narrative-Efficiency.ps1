function ConvertTo-SystemV7StrictCanonicalResponse {
    param([Parameter(Mandatory)][string]$Text)
    # Reject ambiguous property names before PowerShell can collapse them.
    $document=[Text.Json.JsonDocument]::Parse($Text)
    try {
        $check={param($node)
            if($node.ValueKind -eq [Text.Json.JsonValueKind]::Object){
                $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach($property in $node.EnumerateObject()){
                    if(-not $seen.Add($property.Name)){throw 'RESPONSE_DUPLICATE_JSON_KEY'}
                    &$check $property.Value
                }
            }elseif($node.ValueKind -eq [Text.Json.JsonValueKind]::Array){foreach($item in $node.EnumerateArray()){&$check $item}}
        }
        if($document.RootElement.ValueKind -ne [Text.Json.JsonValueKind]::Object){throw 'RESPONSE_JSON_OBJECT_REQUIRED'}
        &$check $document.RootElement
        $data=$Text|ConvertFrom-Json -DateKind String -Depth 64
        if([string]$data.schema -cne 'CONTINUITY_ATTEST_RESULT_V1'){throw 'RESPONSE_SCHEMA_UNSUPPORTED'}
        ConvertTo-SystemV7CanonicalJson -Value $data
    }finally{$document.Dispose()}
}

function Get-SystemV7K4ResponseTemplate {
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][object]$BundleData)
    $lens=[string]$BundleData.run_type
    if($lens -notin @('EDITOR','VERIFY','COLD_READER')){throw 'RESPONSE_TEMPLATE_RUN_TYPE_INVALID'}
    $identity=Get-SystemV7K4BundleDraftIdentityState -Lens $lens -BundleData $BundleData
    if(-not $identity.Valid){throw 'RESPONSE_TEMPLATE_DRAFT_INVALID'}
    $lines=[Collections.Generic.List[string]]::new()
    foreach($line in @("SCHEMA: K4_${lens}_OUTPUT_V1","LENS: $lens","DRAFT_SHA256: $($identity.Sha256)",'VERDICT: <PASS|FAIL>','CRITICAL_COUNT: <uzupełnij>','MAJOR_COUNT: <uzupełnij>','MINOR_COUNT: <uzupełnij>','REVIEW_ALERT_COUNT: <uzupełnij>')){$lines.Add($line)}
    $registry={param($name,$rows)
        if(@($rows).Count -eq 0){$lines.Add("${name}_JSON: BRAK");return}
        foreach($row in $rows){
            $value=[ordered]@{};foreach($key in $row.Keys){$value[$key]=$row[$key]};$value.status='<PASS|FAIL>'
            $lines.Add("${name}_JSON: "+(ConvertTo-SystemV7CanonicalJson -Value $value).Trim())
        }
    }
    if($lens -eq 'COLD_READER'){
        foreach($i in 1..10){$lines.Add(('Q{0:D2}_RESPONSE: <uzupełnij>' -f $i));$lines.Add(('Q{0:D2}_EVIDENCE: <uzupełnij>' -f $i))}
        foreach($section in @('CONFUSION_AND_DROPOFF','PAYOFF_AND_MEMORY','FINDINGS')){$lines.Add("`n## $section");$lines.Add('<uzupełnij po analizie>')}
    }else{
        $inventory=Get-SystemV7K4BundleInventoryState -ProjectPath $ProjectPath -Lens $lens -BundleData $BundleData
        if(-not $inventory.Valid){throw "RESPONSE_TEMPLATE_INVENTORY_INVALID: $($inventory.Errors -join '; ')"}
        $sections=if($lens -eq 'VERIFY'){@('CLAIM_COVERAGE','SOURCE_LOCATORS_CHECKED','ATTRIBUTION_UNCERTAINTY','CONTRADICTIONS','FINDINGS')}else{@('HOOK_AND_PROMISE','QUESTION_REVEAL_LOGIC','TWO_AXES_AND_STATE_CHANGE','EXPOSITION_TRANSITIONS','VOICE_VIEWER_CONTACT','FINALE','FINDINGS')}
        foreach($section in $sections){
            $lines.Add("`n## $section")
            switch($section){
                'CLAIM_COVERAGE' {&$registry 'COVERAGE' $inventory.Coverage}
                'SOURCE_LOCATORS_CHECKED' {&$registry 'LOCATOR' $inventory.Locators}
                'QUESTION_REVEAL_LOGIC' {&$registry 'NQ' $inventory.Questions;&$registry 'NR' $inventory.Reveals}
                'TWO_AXES_AND_STATE_CHANGE' {&$registry 'ACT' $inventory.Acts}
                'EXPOSITION_TRANSITIONS' {&$registry 'REQUIRED' $inventory.Required}
                'VOICE_VIEWER_CONTACT' {&$registry 'VC' $inventory.ViewerContacts;&$registry 'PREFLIGHT' $inventory.SemanticFindings}
            }
            $lines.Add($(if($section -in @('CLAIM_COVERAGE','SOURCE_LOCATORS_CHECKED','QUESTION_REVEAL_LOGIC','TWO_AXES_AND_STATE_CHANGE','EXPOSITION_TRANSITIONS','VOICE_VIEWER_CONTACT')){'ANALYSIS: <uzupełnij po analizie>'}else{'<uzupełnij po analizie>'}))
        }
    }
    return ($lines -join "`n")+"`n"
}
