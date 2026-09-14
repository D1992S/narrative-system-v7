# NARZĘDZIA SYSTEMU v7

## Rozgałęzienie rewizji

`New-Project.ps1` domyślnie tworzy `2026-08-31_NARRATIVE_V2`. To jedyny wybór dla nowej produkcji. Walidatory zachowują zgodność z istniejącymi projektami; ich artefaktów nie wolno mieszać:

- Narrative V2: `Build-K3PacketsV2.ps1`, `_work/k3/**`, continuity attest, Three-Lens K4, `Approve-K5FinalV2.ps1`;
- legacy: `Validate-Architecture.ps1`, `Build-K3Packets.ps1`, `_work/k3-pakiety/`, dawny K4/K5 i historyczne reguły długości.

## K1-Lite V2

- `k1-lite/Convert-PdfToMarkdown.ps1` — oryginalny PDF zostaje nietknięty; tekst ma fizyczne markery stron, a Tesseract działa tylko na stronach wymagających OCR;
- `k1-lite-v2/Invoke-K1LiteV2.ps1` — plan 100% korpusu, maksymalnie dwa workery, append-only ledger, decyzje, visual QA, widok redakcyjny i sześć bramek;
- `Compile-K1LiteV2.ps1` / `Compile-K1LiteV2Corpus.ps1` — Preview i bezpieczny Publish pierwszego `01` z osobnym publish receiptem;
- `Merge-K1LiteV2Supplement.ps1` — addytywny suplement tylko w K2B, z backupem, SHA aktualnej bazy i łańcuchem receiptów;
- `Validate-EvidenceBase.ps1` — zamknięty V4, exact-case pola, hashe, lokalizatory, dosłowne cytaty i fail-closed residue.

Compile jest dozwolony tylko w K1, Merge tylko w K2B. Oba ponownie odczytują etap pod blokadą. Manual fallback wymaga aktualnego receiptu Dawida i nie jest drugim aktywnym pipeline’em.

## Stan i integralność

- `Project-Origin.ps1` — niezmienna tożsamość i bezpieczne ścieżki;
- `Integrity-Receipts.ps1` — project lock, CAS, canonical JSON, journal i wspólne receipty;
- `Advance-Stage.ps1` — preview oraz jedyny commit naprzód;
- `Reopen-Stage.ps1` — jedyny legalny powrót: pełne trasy Narrative V2 oraz utrzymany legacy `2026-08-30_K1_LITE_V2` na trasie `K3→K2B`, zawsze z receiptem i archiwizacją zależnych artefaktów;
- Block/Unblock, `Close-W0Condition.ps1`, `Approve-OwnerOverride.ps1` — związane decyzje;
- `Validate-Project.ps1` — router legacy/V2;
- `Validate-NarrativeV2Project.ps1` — pełny kontrakt Narrative V2.
- `New-NarrativeInstructionManifest.ps1` — preview lub świadomy `-Write` zamkniętego manifestu SHA-256 instrukcji V2.

Każdy mutator odczytuje stan pod lockiem. Advance obejmuje trwałe pliki pełnym manifestem i rollbackiem. Ręczna zmiana stanu, rewizji, czasu, modelu, prefixu, głosu albo proofów jest niedozwolona.

## Story Engine i K3 Narrative V2

- `Narrative-V2.ps1` — architektura, projekcje, atomicity, semantic preflight, continuity i instruction contract;
- `Narrative-Receipts.ps1` — input profiles, run receipts, K4 inventory, fingerprints i carry-forward;
- `Approve-VoiceProfile.ps1`, `Set-VoiceProfileForProject.ps1` — centralny profil oraz jawny wybór Dawida;
- `Set-K3ModelManifest.ps1`, `Rebase-K3Model.ps1` — jeden model, rewizja i SHA ustawień;
- `Build-K3PacketsV2.ps1` — stable prefix, pełne legalne karty, packet, constraint ledger i deterministyczny zapis;
- `Start-K3ConstraintPreflight.ps1` — świeży kontrolny run atomicity;
- `Start-K3Act.ps1`, `Import-K3Act.ps1` — jeden świeży kontekst Claude’a i kontrolowany import;
- `Import-K3BeatSheet.ps1`, `Start-K3BeatPreflight.ps1` — tylko dla aktów `COMPLEX`;
- `Start-ContinuityAttest.ps1`, `Accept-ContinuityAttest.ps1` — niezależny blind attest;
- `Approve-NarrativeMoveRepetition.ps1` — jawna decyzja Dawida dla świadomego powtórzenia ruchu;
- `Assemble-K3Draft.ps1` — montaż wyłącznie kolejnych, atestowanych aktów.

Packet ma najwyżej siedem atomowych CID. `PACKET_INSUFFICIENT` nie może zawierać prozy. Akt następny nie rusza bez PASS poprzedniego atestu. `-AuditExistingAct` w builderze jest wyłącznie read-only ścieżką walidatora, nie skrótem kolejności.

## Three-Lens K4 i K5

- `Start-K4Lenses.ps1` — trzy rozłączne bundle: `EDITOR_V2`, `VERIFY_SOURCE_FIRST_V1`, `COLD_READER_BLIND_V1`;
- `New-NarrativeRunReceipt.ps1` — zamknięty provenance receipt outputu modelu z obowiązkową telemetrią lokalną i opcjonalnym `-TelemetryPath` zgodnym z `_SYSTEM/NARRATIVE/RUN-TELEMETRY-SCHEMA.md`;
- `Compile-K4ProofSet.ps1` / `Compile-K4Reports.ps1` — jeden proof set i kanoniczne `04`/`04B`;
- `Start-QAImpactReview.ps1`, `New-QACarryForwardReceipt.ps1` — selektywny rerun/carry po zmianie;
- `Set-DurationPolicy.ps1`, `Measure-Script.ps1` — `GUIDE` albo finalny `HARD_MAX`, bez targetów per akt;
- `Approve-K5FinalV2.ps1` — jawna, hash-bound akceptacja finalnej narracji.

Editor dostaje semantic preflight związany z draftem, architekturą, voice exemplars i blokami. Verify ma prawdziwe źródła i lokalizatory. Cold Reader dostaje tylko czystą narrację. Różne soczewki muszą mieć różne `RUN_ID` i `TASK_ID`.

## Testy

- `Test-NarrativeV2.ps1` — pozytywne, negatywne, tamper, stale, continuity, semantic, K4/K5 i wydajność nowej rewizji;
- `Test-NarrativeV2-SemanticVerify.ps1` — osobny real-model case; bez outputu i receiptu zwraca uczciwe `NOT_RUN`;
- `Test-AdvanceAtomicity.ps1` — manifest, CAS, journal i rollback;
- `Test-ProjectMutationLocks.ps1` — współbieżność mutatorów;
- `Test-System.ps1` — pełny non-regression legacy/K1/K2B i testy integracyjne.

Parser nigdy nie może zamienić braku realnej kontroli semantycznej w PASS. Voice profile, A/B i aktywacja pilota pozostają decyzjami Dawida.
