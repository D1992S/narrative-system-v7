# AUTOMATYZACJE I OSZCZĘDNOŚĆ PRACY

## Co robi lokalna warstwa

- zachowuje oryginalny PDF, tworzy tekst z fizyczną mapą stron i używa Tesseract tylko na stronach wymagających OCR;
- rozlicza 100% korpusu w rozłącznych paczkach K1, maksymalnie dwoma workerami, oraz zapisuje append-only ledger;
- sprawdza hashe, cytaty, lokalizatory, porządek strony i visual receipts;
- buduje małe widoki redakcyjne, sześć bramek runu, podgląd publikacji i hash-bound publish receipt;
- blokuje Compile poza K1 i Merge poza K2B, ponownie czytając etap pod lockiem;
- utrzymuje niezmienny origin, wspólny lock projektu, pełne manifesty mutacji, CAS, journal, rollback i łańcuch decyzji;
- kompiluje Story Engine do stable prefixu i małego packetu pojedynczego aktu;
- liczy wszystkie twarde obowiązki jednym constraint ledgerem i blokuje ponad siedem atomowych CID;
- tworzy zamknięte input bundle dla preflightu, autora, continuity attest oraz trzech niezależnych soczewek K4;
- wiąże każdy run z `RUN_ID`, `TASK_ID`, modelem, rewizją, SHA ustawień, wejściami i outputem;
- montuje `03-draft.md` tylko z kolejnych, atestowanych aktów;
- wykrywa powtórzenia ruchów, semantic review alerts, skażenie finalnej narracji i stale dependencies;
- buduje `QA_IMPACT`, selektywny rerun albo zweryfikowany carry-forward;
- egzekwuje `GUIDE`/`HARD_MAX` dopiero na poziomie całej narracji, bez limitów per akt;
- kompiluje proof set K4 i akceptację K5 bez fałszywego PASS.

## Co pozostaje osądem

- Dawid wybiera wątki, rozstrzyga konflikty, zatwierdza exact AUTHOR_TEXT, voice profile, politykę czasu, świadome powtórzenia, wyjątki, final K5 i ewentualną aktywację po pilocie;
- ChatGPT/Codex projektuje K2, wykonuje constraint/beat/continuity preflighty, scala K4 i pilnuje prawdy źródłowej;
- Claude jest właścicielem prozy K3, self-checku i propozycji `CONTINUITY_OUT`;
- Editor ocenia narrację, Verify źródła i poziom pewności, a Cold Reader doświadczenie audio-only;
- brak prawdziwego outputu modelu lub ludzkiej decyzji pozostaje `NOT_RUN`, `PENDING` albo `PILOT_ONLY`.

Automaty nie generują decyzji Dawida, nie parafrazują zatwierdzonego AUTHOR_TEXT i nie uznają parserowego PASS za dowód poprawności semantycznej.

## Oszczędność kontekstu

Największa oszczędność pochodzi z tego, że model dostaje tylko pracę, którą ma wykonać:

- K1 analizuje małe paczki, ale ledger rozlicza cały materiał;
- K2 pracuje na bazie dowodów i handoffie, nie na surowym korpusie;
- K3 dostaje byte-identical stable prefix, pełne legalne karty bieżącego aktu i mały packet;
- każdy akt powstaje w świeżym kontekście, więc rozmowa nie rośnie z aktu na akt;
- beat preflight działa tylko dla `COMPLEX`;
- continuity attest dostaje tylko IN, OUT, bloki prozy i schemat;
- Cold Reader uruchamia się raz na pełnym tekście;
- po korekcie ponawia się tylko zależne akty lub soczewki.

Nie wolno oszczędzać przez skracanie kart REQUIRED, exemplarów głosu, poziomu niepewności, lokalizatorów, atestów albo niezależnego Verify.

## Cache i telemetria

Stable prefix jest deterministyczny i ma `PREFIX_SHA256`, więc środowisko może wykorzystać prompt cache. Cache jest opcjonalny: miss nie blokuje pilota i nie zmienia funkcji ani jakości. System nie deklaruje oszczędności, dopóki środowisko nie zwróci rzeczywistych danych cache.

Każdy run receipt zawiera lokalnie policzone bytes, estymację tokenów, czas i status. Jeżeli wykonawca udostępnia dokładne dane, może dodać prefix/source-card/output tokens, retry, cache read/write i koszt zgodnie z `_SYSTEM/NARRATIVE/RUN-TELEMETRY-SCHEMA.md`. Błąd telemetrii nie usuwa poprawnego artefaktu. Nie zapisuje się ukrytego toku rozumowania.

## Narzędzia Narrative V2

- `Narrative-V2.ps1`, `Narrative-Receipts.ps1` — wspólne schematy, canonical JSON, hashe, input profiles, receipty i dependency fingerprints;
- `New-NarrativeInstructionManifest.ps1` — kontrolowane odtworzenie zamkniętego manifestu 58 kluczowych instrukcji po świadomej zmianie systemu;
- `Build-K3PacketsV2.ps1` — stable prefix, packet, selection, constraint ledger, embargo, write command i deterministyczny preview/write;
- `Set-VoiceProfileForProject.ps1`, `Set-K3ModelManifest.ps1`, `Rebase-K3Model.ps1` — zamrożenie głosu i modelu;
- `Start-K3ConstraintPreflight.ps1`, `Start-K3BeatPreflight.ps1`, `Start-K3Act.ps1` — rozłączne bundle runów;
- `Import-K3BeatSheet.ps1`, `Import-K3Act.ps1` — kontrolowany import bez przejmowania autorstwa przez orkiestratora;
- `Start-ContinuityAttest.ps1`, `Accept-ContinuityAttest.ps1`, `Assemble-K3Draft.ps1` — ślepy atest, sekwencja i montaż;
- `Start-K4Lenses.ps1`, `Compile-K4ProofSet.ps1`, `Compile-K4Reports.ps1` — Editor V2, Verify source-first, Cold Reader i jeden proof set;
- `Start-QAImpactReview.ps1`, `New-QACarryForwardReceipt.ps1`, `Reopen-Stage.ps1` — formalna korekta i inwalidacja;
- `Set-DurationPolicy.ps1`, `Measure-Script.ps1` — polityka i pomiar czasu;
- `Approve-K5FinalV2.ps1` — hash-bound akceptacja finalnej narracji;
- `Validate-NarrativeV2Project.ps1`, `Test-NarrativeV2.ps1` — pełny kontrakt i regresje nowej rewizji.

## Narzędzia K1 i wspólnego stanu

- `k1-lite/Convert-PdfToMarkdown.ps1` — konwersja i selektywny OCR;
- `k1-lite-v2/Invoke-K1LiteV2.ps1` — plan, import, decyzje, visual QA, widoki i sześć bramek;
- `Compile-K1LiteV2.ps1`, `Compile-K1LiteV2Corpus.ps1`, `Merge-K1LiteV2Supplement.ps1` — bezpieczna publikacja i suplement;
- `Project-Origin.ps1`, `Integrity-Receipts.ps1` — origin, lock, CAS, journal i immutable receipts;
- `Advance-Stage.ps1`, `Reopen-Stage.ps1`, Block/Unblock — jedyne legalne mutacje etapu;
- `Validate-EvidenceBase.ps1`, `Validate-Project.ps1` — walidacja źródeł i rozgałęzienie według rewizji.

`Validate-Architecture.ps1`, `Build-K3Packets.ps1`, `New-K4VerifyReceipt.ps1` i legacy część `Approve-K5Final.ps1` obsługują utrzymany tor `2026-08-30_K1_LITE_V2`. Narrative V2 nie może tworzyć `_work/k3-pakiety/`, używać budżetu aktu ani dawnego K3 approval override.
