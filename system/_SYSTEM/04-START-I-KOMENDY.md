# START I KOMENDY

W każdym poleceniu ustaw jawnie pełną ścieżkę projektu:

```powershell
$project = "E:\projektyoutube\Produkcja tekstów\projekty\Nazwa filmu"
$tools = "E:\projektyoutube\Produkcja tekstów\System-v7.0\tools"
```

Nie istnieje globalny `ACTIVE_PROJECT`. Polecenia bez `-Apply` albo `-Write` są podglądem, jeśli dokumentacja danego narzędzia nie mówi inaczej.

## Nowy projekt Narrative V2

Narrative V2 jest jedynym domyślnym wyborem dla nowego projektu. Zachowuje status jakości `PILOT_ONLY`, dopóki nie zostanie zakończony test A/B:

```powershell
& "$tools\New-Project.ps1" `
  -ProjectName "Nazwa filmu" `
  -DestinationRoot "E:\projektyoutube\Produkcja tekstów\projekty" `
  -Channel dawid_soltan -Format STORYTELLING `
  -TargetMinutes 45 -TargetDurationMode GUIDE `
  -NarrativeV2Pilot
```

Przełącznik `-NarrativeV2Pilot` jest opcjonalny: jego pominięcie również tworzy Narrative V2. Nie wolno przerabiać ręcznie starszego projektu przez zmianę `WORKFLOW_REVISION`. Projekt historyczny można zarejestrować do walidacji:

```powershell
& "$tools\Register-LegacyProject.ps1" -ProjectPath $project `
  -Reason "Konkretny powód rejestracji archiwalnej" -DawidApproved
```

## Źródła i K1-Lite V2

Aktywne PDF/MD/TXT/SRT/VTT umieść bezpośrednio w `sources/`; zaplecze wyłącznie w `sources/_oryginaly/`. PDF zachowuje oryginał. Konwersja tworzy tekst z markerami stron, a OCR Tesseract dotyczy wyłącznie stron, które go wymagają.

Typowa trasa K1:

1. utwórz plan i run K1-Lite V2;
2. wykonaj ekstrakcję całego korpusu maksymalnie dwoma workerami;
3. zbuduj widoki i pokaż Dawidowi `editorial-review.md`;
4. zapisz decyzje `AddReview` i ponownie zbuduj widoki;
5. uruchom świeży `ValidateRun` — wszystkie sześć bramek muszą przejść;
6. wykonaj Compile Preview, a potem Publish z dokładnymi SHA ledgera i podglądu;
7. sprawdź canonical:

```powershell
& "$tools\Validate-EvidenceBase.ps1" -ProjectPath $project
```

`STRUCTURE_PASS`, `GateReady: True` i `ManualCheckCards: 0` nie zastępują aktualnego editorial receiptu, publish receiptu ani sześciu bramek runu. Compile jest legalny wyłącznie w K1. Suplement przez `Merge-K1LiteV2Supplement.ps1` jest legalny wyłącznie w K2B, po takim samym przeglądzie i Preview; oba skrypty ponownie odczytują etap pod blokadą i nie zostawiają outputu przy odmowie.

Manual fallback istnieje wyłącznie po jawnej zgodzie Dawida i własnym receipcie. Nie jest skrótem dla nieudanego automatycznego K1.

## Przejścia W0–K2B

Każdy etap kończysz przez realny podgląd i commit:

```powershell
& "$tools\Validate-Project.ps1" -ProjectPath $project
& "$tools\Advance-Stage.ps1" -ProjectPath $project
& "$tools\Advance-Stage.ps1" -ProjectPath $project -Apply
```

Tylko W0 → K0 wymaga dodatkowo `-DawidApproved` w commicie. `GO WARUNKOWE` wymaga przed K0 → K1:

```powershell
& "$tools\Close-W0Condition.ps1" -ProjectPath $project `
  -Result "Konkretny wynik realizacji warunku" -DawidApproved
```

K2 dla Narrative V2 tworzy `STORY_ENGINE_V2`: Story DNA, drabinę stanu widza, NQ, NR, VC, Scene Weave, funkcje dowodów, completion criteria i najwyżej siedem atomowych CID na akt. Nie zawiera budżetów słów, znaków, dolnych progów ani limitów per akt. Sprawdzenie bieżącej rewizji:

```powershell
& "$tools\Validate-NarrativeV2Project.ps1" -ProjectPath $project
```

Jedyny kierunek może nadal wymagać jawnego wyjątku K2, ale Narrative V2 odrzuca `K3_BUDGET_OVERRIDE`. Dawne komendy `Validate-Architecture.ps1` i `Build-K3Packets.ps1` dotyczą wyłącznie legacy.

## Zamrożenie głosu i modelu

Centralny profil głosu nie może zostać użyty jako zatwierdzony, dopóki Dawid nie zaakceptuje dokładnych reguł i dosłownych exemplarów:

```powershell
& "$tools\Approve-VoiceProfile.ps1" -ProfilePath "...\DAWID-V1.md" `
  -ApprovalNote "Dokładny zakres zatwierdzonych próbek" -DawidApproved

& "$tools\Set-VoiceProfileForProject.ps1" -ProjectPath $project `
  -ProfilePath "...\DAWID-V1.md" `
  -ApprovalNote "Profil wybrany do tego projektu" -DawidApproved
```

W K2B zamroź jeden model, rewizję i jawny plik ustawień JSON:

```powershell
& "$tools\Set-K3ModelManifest.ps1" -ProjectPath $project `
  -ModelId "claude-sonnet" -ModelRevision "dokładna-rewizja" `
  -ModelSettingsPath "$project\_work\model-settings.json"
```

Po użyciu modelu zmiana wymaga `Rebase-K3Model.ps1`; ręczna podmiana pól meta daje FAIL.

## K3 — packet, preflight, akt i atest

K3 zawsze działa sekwencyjnie: jeden akt, jeden świeży kontekst Claude’a, jeden model i ten sam stable prefix. Poniższy cykl powtarza się dla kolejnego `ACT_ID`.

### 1. Deterministyczna paczka

```powershell
& "$tools\Build-K3PacketsV2.ps1" -ProjectPath $project -ActId ACT-001
& "$tools\Build-K3PacketsV2.ps1" -ProjectPath $project -ActId ACT-001 -Write
```

Packet zawiera tylko compiled core, Story Spine, voice profile, `CONTINUITY_IN`, wybrane pełne karty, ACT packet, do siedmiu atomowych ograniczeń i polecenie pisania. Nie przekazuj Claude’owi pełnej Biblii narracji ani całego korpusu.

### 2. Constraint preflight

```powershell
$preflightRun = "K3-CID-ACT001-0001"
& "$tools\Start-K3ConstraintPreflight.ps1" -ProjectPath $project -ActId ACT-001 -RunId $preflightRun
```

Uruchom osobny świeży kontekst ChatGPT/Codex wyłącznie z utworzonego bundle. Zapisz wynik i utwórz receipt:

```powershell
& "$tools\New-NarrativeRunReceipt.ps1" -ProjectPath $project `
  -RunId $preflightRun -OutputPath "<OUTPUT>" -TaskId "<TASK_ID>" `
  -ModelId "<MODEL>" -ModelRevision "<REVISION>" `
  -ModelSettingsSha256 "<SHA256>" -PromptRevision "CONSTRAINT_PREFLIGHT_V1" `
  -ActorRole CHATGPT_CODEX -StartedAt "<ISO-8601>"
```

PASS ustawia packet jako READY. Ciche pominięcie CID, ukryta lista kilku nakazów albo ponad siedem obowiązków blokuje pisanie.

Jeżeli wykonawca udostępnia prawdziwe dane tokenów, cache i kosztu, zapisz je jako `_work/narrative-runs/<RUN_ID>/provider-telemetry.json` i dodaj do komendy receiptu `-TelemetryPath <PLIK>`. Bez tego system nadal zapisuje lokalne bajty, estymację tokenów i czas; brak cache lub błędna telemetria nie blokują poprawnego outputu. Dokładny kontrakt: `_SYSTEM/NARRATIVE/RUN-TELEMETRY-SCHEMA.md`.

### 3. Świeży kontekst autora

```powershell
$generateRun = "K3-GEN-ACT001-0001"
& "$tools\Start-K3Act.ps1" -ProjectPath $project -ActId ACT-001 -RunId $generateRun
```

Claude najpierw ocenia wystarczalność. `PACKET_INSUFFICIENT` musi mieć zero prozy i dokładną trasę naprawy. Przy PASS:

```powershell
& "$tools\Import-K3Act.ps1" -ProjectPath $project -ActId ACT-001 `
  -RunId $generateRun -SubmissionPath "<SUBMISSION_JSON>"
```

Dla aktu `COMPLEX` importuje się beat sheet, uruchamia `Start-K3BeatPreflight.ps1`, tworzy niezależny receipt i dopiero po PASS wraca do tej samej sesji autora. Akt `SIMPLE` nie tworzy sztucznego beat sheetu.

Po prozie Claude proponuje `CONTINUITY_OUT`; import FINALIZE wiąże tę samą sesję i jej czas. Następnie:

```powershell
$attestRun = "K3-ATT-ACT001-0001"
& "$tools\Start-ContinuityAttest.ps1" -ProjectPath $project -ActId ACT-001 -RunId $attestRun
```

Atest uruchamiasz w innym świeżym kontekście tylko z blokami prozy, IN, OUT i schematem. Po prawdziwym PASS i receipcie:

```powershell
& "$tools\Accept-ContinuityAttest.ps1" -ProjectPath $project `
  -ActId ACT-001 -RunId $attestRun
```

Następny akt nie może ruszyć przed ważnym atestem. Powtórzenie typu otwarcia/zamknięcia daje alert; świadomy wyjątek zatwierdza wyłącznie Dawid:

```powershell
& "$tools\Approve-NarrativeMoveRepetition.ps1" -ProjectPath $project `
  -Reason "Konkretny powód świadomego powtórzenia" -DawidApproved
```

Po wszystkich aktach:

```powershell
& "$tools\Assemble-K3Draft.ps1" -ProjectPath $project
& "$tools\Validate-NarrativeV2Project.ps1" -ProjectPath $project
& "$tools\Advance-Stage.ps1" -ProjectPath $project
& "$tools\Advance-Stage.ps1" -ProjectPath $project -Apply
```

`03-draft.md` jest montowany deterministycznie. Czysta narracja nie zawiera `#P`, `BLOCK_ID`, nagłówków technicznych ani komentarzy.

## K4 — trzy niezależne soczewki

W K4 utwórz trzy różne runy:

```powershell
& "$tools\Start-K4Lenses.ps1" -ProjectPath $project `
  -EditorRunId "K4-EDITOR-0001" `
  -VerifyRunId "K4-VERIFY-0001" `
  -ColdReaderRunId "K4-COLD-0001"
```

- `EDITOR_V2` dostaje architekturę, głos, block map, continuity i związany `SEMANTIC_PREFLIGHT`;
- `VERIFY_SOURCE_FIRST_V1` dostaje draft, bazę, źródła i lokalizatory, bez kryteriów stylu;
- `COLD_READER_BLIND_V1` dostaje tylko czystą narrację i neutralne pytania.

Każdy wynik powstaje w osobnym świeżym kontekście, ma inny `TASK_ID` i własny `New-NarrativeRunReceipt.ps1`. Wyniki jednej soczewki nie są wejściem drugiej. Po trzech prawdziwych PASS:

```powershell
& "$tools\Compile-K4Reports.ps1" -ProjectPath $project `
  -EditorRunId "K4-EDITOR-0001" -VerifyRunId "K4-VERIFY-0001" `
  -ColdReaderRunId "K4-COLD-0001"
```

Kompilator buduje hash-bound `K4_PROOF_SET_V2`, `04` i `04B`. Alert semantyczny musi zostać jawnie rozpatrzony przez Editora. Verify ma pierwszeństwo w sprawach faktu, a ładna proza z zawyżoną pewnością ma dostać FAIL.

Zmiana prozy wymaga formalnego `Reopen-Stage.ps1` do K3; zmiana źródeł/architektury — do K2B. Po nowym drafcie każda soczewka wymaga świeżego runu albo ważnego, acyklicznego carry-forward opartego na `QA_IMPACT`; zmiana semantic preflight zawsze zmienia fingerprint Editora.

## Reopen i polityka czasu

```powershell
& "$tools\Reopen-Stage.ps1" -ProjectPath $project -TargetStage K3 `
  -ReasonCode PROSE_CORRECTION -Scope "ACT-002: dokładna korekta sceny" `
  -FromActId ACT-002 -DawidApproved

& "$tools\Set-DurationPolicy.ps1" -ProjectPath $project -Mode HARD_MAX `
  -TargetMinutes 45 -Reason "Konkretny limit publikacyjny" -DawidApproved
```

`GUIDE` mierzy po napisaniu i nie tworzy dolnego progu. `HARD_MAX` blokuje dopiero finalną całość przekraczającą limit. Żaden tryb nie tworzy targetów per akt.

## K5 i COMPLETE

Po realnym K4 PASS przejdź przez `Advance-Stage.ps1` do K5. `05-FINAL-SCRIPT.md` musi zawierać metadane techniczne poza sekcją mówioną i samą narrację w sekcji finalnej. Pomiar:

```powershell
& "$tools\Measure-Script.ps1" -ScriptPath "$project\05-FINAL-SCRIPT.md"
```

Po jawnej akceptacji Dawida:

```powershell
& "$tools\Approve-K5FinalV2.ps1" -ProjectPath $project `
  -ApprovalNote "Akceptuję dokładnie tę finalną narrację" -DawidApproved
& "$tools\Advance-Stage.ps1" -ProjectPath $project
& "$tools\Advance-Stage.ps1" -ProjectPath $project -Apply
```

Prawidłowy finał ma `CURRENT_STAGE: COMPLETE`, `LAST_GATE: K5_PASS`, właściciela Dawid i ważny K5 receipt. Nie ustawiaj tego ręcznie.

## Blokada, owner override i walidacja

```powershell
& "$tools\Block-Project.ps1" -ProjectPath $project `
  -Reason "Konkretny bloker" -DawidApproved
& "$tools\Unblock-Project.ps1" -ProjectPath $project `
  -Resolution "Konkretny sposób rozwiązania" -DawidApproved

& "$tools\Approve-OwnerOverride.ps1" -ProjectPath $project -Owner ChatGPT `
  -Reason "Konkretny powód" -Scope "Dokładny zakres" -DawidApproved
```

Nie edytuj ręcznie pól receipt, właściciela ani stanu. Pełny walidator Narrative V2:

```powershell
& "$tools\Validate-NarrativeV2Project.ps1" -ProjectPath $project
```

## Regresja systemu

Po zmianie samych narzędzi uruchom testy; narzędzia nie należą do manifestu 58 instrukcji:

```powershell
& "$tools\Test-NarrativeV2.ps1"
& "$tools\Test-AdvanceAtomicity.ps1"
& "$tools\Test-ProjectMutationLocks.ps1"
& "$tools\Test-System.ps1"
```

`New-NarrativeInstructionManifest.ps1 -Write` wolno uruchomić wyłącznie po świadomej zmianie pliku z zamkniętej allowlisty, po ręcznym przeglądzie diffu tej instrukcji. Po odtworzeniu manifestu zawsze uruchom pełny zestaw testów powyżej; nie używaj `-Write` do „naprawiania” przypadkowego tamperu.

Test semantyczny z prawdziwym modelem jest osobny i nie może fałszywie przejść bez outputu oraz receiptu:

```powershell
& "$tools\Test-NarrativeV2-SemanticVerify.ps1" -AuditFakePass -NoExit
```

`NOT_RUN` nie jest PASS. Ślepy test A/B jest opisany w `_SYSTEM/NARRATIVE/AB-TEST-PROTOCOL.md`, a jego prawdziwy stan w `AB-TEST-STATUS.json`. Akceptacja voice profile i A/B pozostają decyzjami Dawida; do tego czasu `WORKFLOW_ACTIVATION` ma pozostać `PILOT_ONLY`.
