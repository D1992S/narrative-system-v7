# Mapa zależności wdrożenia NARRATIVE_V2

STATUS: ZAMROŻONA

## Wersja, origin i dostęp do projektu

- `tools/Project-Origin.ps1` — rejestr rewizji, origin i rozróżnienie mutable/read-only.
- `tools/New-Project.ps1` — tworzenie originu i szablonów.
- `tools/Start-Stage.ps1`, `tools/Advance-Stage.ps1` — mutatory etapów.
- `tools/Block-Project.ps1`, `tools/Unblock-Project.ps1`, `tools/Close-W0Condition.ps1` — mutatory stanu.
- `tools/Approve-OwnerOverride.ps1` — mutator właściciela; musi wymagać nowego originu, bieżącej rewizji i fail-closed dla wszystkich projektów read-only.
- `tools/Approve-K1ManualFallback.ps1` — zapisuje receipt K1; musi rozgałęziać origin/revision i blokować zapis do projektów validation-only.
- `tools/Register-LegacyProject.ps1` — jedyna jawna rejestracja dawnych originów; nie może przejąć projektów `2026-08-30_K1_LITE_V2`, które już mają ważny `project-origin.json`.
- `tools/Validate-Project.ps1`, `tools/Validate-EvidenceBase.ps1`, `tools/Validate-Architecture.ps1` — rozgałęzienie walidacji według rewizji.
- K1 i źródła: `Compile-K1LiteV2.ps1`, `Compile-K1LiteV2Corpus.ps1`, `Merge-K1LiteV2Supplement.ps1`, `K1-PublishIntegrity.ps1`, `Build-SourceInventory.ps1`, `Build-SourceManifest.ps1`, `Search-Sources.ps1`, `New-K4VerifyReceipt.ps1`. `Build-SourceInventory.ps1` pozostaje warstwą wejścia K1 bez przebudowy kart, ale podlega kontroli ścieżek i rewizji wywołującego procesu.

## K2, K3 i długość

- Dokumenty kontraktowe: `AGENTS.md`, `_SYSTEM/00-KONSTYTUCJA.md`, `_SYSTEM/01-PIPELINE.md`, `_SYSTEM/02-ROLE-I-ODPOWIEDZIALNOSC.md`, `_SYSTEM/03-STAN-I-PLIKI.md`, `_SYSTEM/04-START-I-KOMENDY.md`, `_SYSTEM/06-AUTOMATYZACJE.md`.
- Kroki: `_SYSTEM/STEPS/K2-ARCHITEKTURA.md`, `K2B-SUPLEMENT.md`, `K3-SCENARIUSZ.md`.
- Role i warsztat: `_SYSTEM/ROLES/*.md`, `_SYSTEM/SKILLS/*.md`, `BIBLIA/*.md`.
- Szablony: `00-fundament-projektu.md`, `meta.md`, `02-architektura-odcinka.md`, `03-draft.md`.
- Narzędzia: `Build-K3Packets.ps1`, `Measure-Script.ps1`, `Check-Repetition.ps1`, `Approve-EditorialException.ps1`.
- Stare zależności do rozgałęzienia: `Budżet słów`, `TARGET_MINUTES × REAL_WPM`, `70–140%`, `300 słów/PRIMARY`, `K3_BUDGET_OVERRIDE`.

## Ciągłość, K4 i final

- `_SYSTEM/STEPS/K4-QA-FACTCHECK.md`, `_SYSTEM/STEPS/K5-FINAL.md`.
- `TEMPLATES/PROJECT/04-raport-qa.md`, `04B-fact-check.md`, `05-FINAL-SCRIPT.md`.
- `Integrity-Receipts.ps1`, `Compare-Draft.ps1`, `New-K4VerifyReceipt.ps1`, `Approve-K5Final.ps1`.
- Nowe wymagane mutatory: reopen, duration policy, receipty runów/atestu/carry-forward i deterministyczny montaż aktów.

## Dokumentacja i testy

- `README.md`, `tools/README.md`, `AUDYT-KOMPLETNOSCI.md`, `MAPA-SYSTEMU.md`, `Proces-v7.0.canvas`, `CHANGELOG.md`.
- `Test-System.ps1`, `Test-AdvanceAtomicity.ps1`, `Test-ProjectMutationLocks.ps1` oraz testy K1-Lite.
- `tools/New-SystemV7Manifest.ps1` — wyłącznie deterministyczny generator audytowego manifestu baseline; nie jest mutatorem projektu runtime.
- Test skanu wycofanych etapów musi rozróżniać dawną nazwę etapu od etykiety priorytetu audytu; zmiana treści audytu nie jest naprawą.

## Kolejność bezpiecznej implementacji

1. Mapowanie originów: nowa rewizja mutowalna jako pilot, `2026-08-30_K1_LITE_V2` mutowalna jako utrzymany tor zgodności, starsze rejestracje legacy wyłącznie validation-only i bez automigracji.
2. Kontrakt i schematy NARRATIVE_V2.
3. K2 Story Engine i walidacja bez budżetów aktów.
4. Sekwencyjny kompilator K3, run manifest, continuity OUT/ATTEST i montaż draftu.
5. Reopen, trzy soczewki K4, impact/carry-forward i bramka K5.
6. Rozgałęzienie wszystkich mutatorów i receiptów K1/K4.
7. Testy pozytywne, negatywne, atomowości, PDF i legacy.
8. Synchronizacja dokumentów, mapy i Canvas.

## Niezmienniki

- Trasa pozostaje `W0 → K0 → K1 → K2 → K2B → K3 → K4 → K5 → COMPLETE`.
- Claude pozostaje wyłącznym autorem prozy K3; ChatGPT nie przejmuje pisania.
- Dawid pozostaje właścicielem W0, K5, `AUTHOR_TEXT`, polityki `HARD_MAX`, migracji i finalnej aktywacji.
- `MINIMAL_EVIDENCE_V4_PAGELOC` i zawartość kart K1 nie są przebudowywane przez narrację.
- Brak zatwierdzonych exemplarów oznacza fail-closed/PILOT, nigdy fikcyjne zatwierdzenie Dawida.
