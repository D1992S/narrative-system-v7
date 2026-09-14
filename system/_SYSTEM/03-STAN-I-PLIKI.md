# STAN PROJEKTU I PLIKI

## Jedyny stan

`meta.md` jest jedynym kanonicznym stanem bieżącym. Historia decyzji i mutacji istnieje w niezmiennych receiptach oraz w `ARCHIWUM ZMIAN`; sama deklaracja wpisana do Markdown nie zastępuje receiptu.

Nowy projekt narracyjny musi mieć jednocześnie:

- `WORKFLOW_REVISION: 2026-08-31_NARRATIVE_V2`;
- `WORKFLOW_ACTIVATION: PILOT_ONLY`;
- `ARCHITECTURE_SCHEMA: STORY_ENGINE_V2`;
- `K3_PACKET_SCHEMA: K3_PACKET_V2`;
- `CONTINUITY_SCHEMA: CONTINUITY_ATTEST_V1`;
- `K4_QA_SCHEMA: THREE_LENS_QA_V1`.

Wymagane grupy pól `meta.md`:

- tożsamość: `SYSTEM_VERSION`, rewizja i aktywacja, `EVIDENCE_SCHEMA`, wszystkie cztery schematy narracyjne, `PROJECT_NAME`, `PROJECT_PATH`;
- stan: `CURRENT_STAGE`, `STAGE_OWNER`, owner override, head receiptu stanu, pola blokady i `LAST_GATE`;
- W0 i źródła: komplet pól decyzji W0, `K1_RESEARCH_MODE`, wersja silnika, run, ledger i publish receipt;
- czas: `TARGET_MINUTES`, `TARGET_DURATION_MODE` (`GUIDE` albo `HARD_MAX`), receipt polityki czasu, `REAL_WPM`, `WPM_STATUS`;
- głos: `VOICE_PROFILE_REVISION`, `VOICE_PROFILE_STATUS`, ścieżka i SHA selection receiptu;
- K3: `K3_MODEL_ID`, rewizja i SHA ustawień, manifest modelu, `K3_PREFIX_SHA256`, `K3_LAST_ATTESTED_ACT`, `NARRATIVE_ACT_SEQUENCE`, `CONTINUITY_STATUS`;
- K4: trzy proof pointery i `K4_PROOF_SET_SHA256`;
- routing: `K2B_DECISION`, `LAST_UPDATED`, `NEXT_ACTION`.

Pola Narrative V2 są kontraktem zamkniętym. Nie wolno dopisywać do nowej architektury ani draftu budżetów słów/znaków, dolnych progów długości ani `K3_BUDGET_OVERRIDE`. Ten wyjątek pozostaje rozpoznawany wyłącznie przez walidator projektów legacy.

## Dozwolone stany i bramki

Dozwolone stany: `W0`, `K0`, `K1`, `K2`, `K2B`, `K3`, `K4`, `K5`, `COMPLETE`, `BLOCKED`.

| `CURRENT_STAGE` | wymagany `LAST_GATE` |
|---|---|
| W0 | `PROJECT_INITIALIZED` |
| K0 | `W0_GO` albo `W0_GO_WARUNKOWE` |
| K1 | `K0_PASS` |
| K2 | `K1_PASS` |
| K2B | `K2_PASS` |
| K3 | `K2B_PASS` |
| K4 | `K3_PASS` |
| K5 | `K4_PASS` |
| COMPLETE | `K5_PASS` |

`Advance-Stage.ps1` bez `-Apply` jest podglądem, a z `-Apply` jedyną legalną drogą naprzód. `Reopen-Stage.ps1` jest jedyną legalną drogą wstecz. Oba mutatory działają pod blokadą projektu, ponownie odczytują stan już pod blokadą, wiążą pełny manifest wejść i wykonują rollback przy błędzie. Ręczna zmiana `CURRENT_STAGE`, rewizji, polityki czasu, prefixu, modelu lub proofów daje FAIL.

`BLOCKED` zachowuje ostatnią prawdziwą bramkę i zapisuje etap oraz konkretną przyczynę. Block/Unblock, owner override, warunek W0, reopen, zmiana czasu, wybór głosu i akceptacja K5 wymagają właściwych immutable receiptów. Pole `actor: DAWID` oznacza audytowalne potwierdzenie decyzji przekazanej narzędziu, a nie kryptograficzne uwierzytelnienie osoby.

## Pochodzenie i legacy

- Bieżący projekt ma `.system-v7/project-origin.json` w schemacie `SYSTEM_V7_PROJECT_ORIGIN_V1`, utworzony przez `New-Project.ps1`.
- Projekt historyczny może dostać `.system-v7/legacy-origin.json` wyłącznie przez `Register-LegacyProject.ps1 -DawidApproved`.
- Utrzymany tor `2026-08-30_K1_LITE_V2` zachowuje własne paczki, budżety i dawny wyjątek budżetowy. Jeszcze starsze, zarejestrowane projekty pozostają validation-only i żaden projekt nie jest automatycznie migrowany.
- Wznowienie projektu starszego niż `2026-08-30_K1_LITE_V2`, zarejestrowanego przez `legacy-origin.json`, wymaga utworzenia nowego projektu i jawnej, odwracalnej migracji treści. Utrzymany tor `2026-08-30_K1_LITE_V2` pozostaje mutowalny według własnego kontraktu. Nie wolno mieszać artefaktów rewizji.

## Kanoniczne i techniczne pliki Narrative V2

```text
Projekt/
├── .system-v7/
│   ├── project-origin.json
│   ├── meta-write.lock
│   └── meta-transactions/
├── meta.md
├── sources/
│   └── _oryginaly/
├── _work/
│   ├── K1/
│   │   ├── k1-lite-v2/
│   │   └── manual-fallback/
│   ├── k2/reopen/
│   ├── k3/
│   │   ├── prefix/
│   │   ├── packets/
│   │   ├── beats/
│   │   ├── acts/<ACT_ID>/
│   │   ├── continuity/
│   │   └── model/
│   ├── k4/
│   │   ├── inputs/
│   │   ├── outputs/
│   │   ├── impact/
│   │   └── proofs/
│   ├── k5/
│   ├── narrative-runs/
│   ├── duration/
│   └── system/
│       ├── editorial-exceptions/
│       ├── owner-override/
│       ├── state-decisions/
│       └── w0-condition/
├── 00-fundament-projektu.md
├── 01-baza-dowodow.md
├── 02-architektura-odcinka.md
├── 03-draft.md
├── 04-raport-qa.md
├── 04B-fact-check.md
└── 05-FINAL-SCRIPT.md
```

Każdy element ma jedno miejsce kanoniczne:

- `02` jest źródłem Story Engine; wygenerowany prefix i packet są kompilatami, nigdy drugim źródłem prawdy;
- `_work/k3/prefix/` przechowuje byte-identical stable prefix i jego SHA;
- `_work/k3/packets/` przechowuje zamknięte paczki aktów, constraint ledger i ich hashe;
- `_work/k3/acts/<ACT_ID>/` przechowuje bloki prozy, self-check, `CONTINUITY_OUT` oraz attestation binding;
- `_work/narrative-runs/` przechowuje zamknięte input bundle i provenance receipty każdego świeżego runu;
- `_work/k4/inputs/` ma trzy rozłączne whitelisty wejść oraz semantic preflight; `outputs/` ma surowe wyniki; `proofs/` jeden proof set;
- `03-draft.md` jest deterministycznym montażem wyłącznie atestowanych aktów;
- `04` i `04B` są kanonicznymi wynikami K4, a `05` finalną, czystą narracją po K5.

Katalog `_work/k3-pakiety/` jest legalny wyłącznie w legacy. Jego obecność w Narrative V2 oznacza `MIXED_SCHEMA_LEGACY_K3_PACKET_DIRECTORY`.

## Źródła i K1

`K1-COMPILED` nie jest plikiem kanonicznym. Pierwszy `01` powstaje wyłącznie po Preview i Publish z aktualnym runem, sześcioma bramkami, editorial receiptem Dawida i hashami. Identyczne ponowienie może odzyskać dokładnie tę samą publikację; inne wejście nie nadpisuje canonicalu.

K2B używa osobnego podglądu scalonej bazy, SHA bieżącego `01`, kopii odzyskiwania i nowego publish receiptu wskazującego poprzedni. Compile jest legalny tylko w K1, Merge tylko w K2B; etap jest ponownie odczytywany pod blokadą. `02A`, `01B` i `02B` pozostają wyłącznie historycznymi plikami starszych projektów.

Aktywne PDF/MD/TXT/SRT/VTT leżą bezpośrednio w `sources/`. `_oryginaly/` jest zapleczem i nie może zawierać jedynej aktywnej kopii. Oryginalny PDF nie jest nadpisywany; konwersja tworzy tekst z markerami fizycznych stron, a OCR Tesseract obejmuje tylko strony, które go wymagają. Visual receipt i hash wiążą układ strony z cytatem. Zmiana źródła wymaga nowego planu i runu K1.

## Rewizje, hashe i inwalidacja

Narrative V2 zamraża na czas projektu: aktywną instrukcję, model i ustawienia, voice profile, prefix oraz sekwencję aktów. Zmiana globalnego Story Spine, exemplarów, modelu lub kontrolowanego pliku instrukcji unieważnia zależne packety, prozę i atesty. Lokalna zmiana aktu unieważnia tylko jego projekcję i downstream continuity, o ile globalne hashe pozostają identyczne.

Każdy run ma własny `RUN_ID`, `TASK_ID`, manifest wejść i receipt. Autor aktu, continuity attest, Editor, Verify i Cold Reader są rozłącznymi runami. `03`, `04`, `04B` i `05` są hash-bound. Carry-forward jest legalny tylko z aktualnym `OLD_DRAFT_SHA`, `NEW_DRAFT_SHA`, `DIFF_SHA` i nieprzerwanym, acyklicznym łańcuchem; niepewność wymusza rerun.

Polityka długości ma dwa tryby:

- `GUIDE` — pomiar po napisaniu informuje Dawida, ale nie wymusza rozciągania ani skracania aktu;
- `HARD_MAX` — finalna całość nie może przekroczyć limitu, lecz nie powstają limity per akt ani dolny próg.

## Higiena i manifesty

`_work/` nie jest magazynem źródeł ani miejscem dla przypadkowych kopii. Pełny manifest Advance obejmuje wszystkie trwałe pliki i katalogi projektu, w tym `sources/`, `_work/qa-baseline.md`, `_work/k3/**`, `_work/k4/**`, `_work/narrative-runs/**`, receipty czasu i reopen. Wyłącza tylko `meta.md`, nośnik locka oraz dokładne poddrzewo transakcji powstające wskutek commitu.

Instrukcje Narrative V2 mają osobny zamknięty manifest `_SYSTEM/NARRATIVE/NARRATIVE-INSTRUCTION-MANIFEST.json`. Allowlist jest zapisany w kodzie, a manifest zawiera dokładne SHA-256 jego 58 plików. Brak kontrolowanego pliku, dodatkowy wpis, zmiana bajtów, zła kolejność, reparse point albo niezgodny marker AGENTS blokuje nowy projekt i każdą aktywną operację V2 przed pierwszą mutacją. Po świadomej zmianie instrukcji maintainer odtwarza manifest przez `New-NarrativeInstructionManifest.ps1 -Write` i uruchamia regresję; sam projekt nie może tego zrobić. Stable prefix może korzystać z cache, ale cache miss nigdy nie blokuje procesu ani nie zmienia wyniku.

`COMPLETE` oznacza zatwierdzoną finalną narrację, nie ukończony film. Osiąga się go tylko realnym `Advance-Stage.ps1 -Apply` po receipcie akceptacji Dawida; nie wolno symulować tego stanu w metadanych.
