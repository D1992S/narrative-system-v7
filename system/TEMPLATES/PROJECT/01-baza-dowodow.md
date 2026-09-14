# 01 — MINIMALNA BAZA DOWODÓW

K1_SCHEMA: MINIMAL_EVIDENCE_V4_PAGELOC
LOCATOR_POLICY: MIXED_V1
STATUS: ROBOCZY
DATA_ODCIĘCIA:
LEAD_AGENT_ID:
RESEARCH_ROUNDS:
STOP_REASON:
STRUCTURE_CHECK: NIEURUCHOMIONY
SOURCE_FIDELITY_CHECK: NIEURUCHOMIONY
SATURATION_CHECK: NIEURUCHOMIONY
K1_VERDICT: ROBOCZY
K1_ORIGIN:
K1_ORIGIN_VERSION: 2.1.0
K1_EXPORT_PATH:
K1_EXPORT_SHA256:
CORPUS_COVERAGE_REVIEWED: NIE
K0_COVERAGE_REVIEWED: NIE
SOURCE_CLASSES_REVIEWED: NIE

## 1. Pokrycie celów i handoff K2

NIEROZLICZONE_ŹRÓDŁA: NIEUSTALONE

| Cel | Status: POKRYTY / LUKA JAWNA / POZA ZAKRESEM | Najważniejsze #P | Luka/uwaga |
|---|---|---|---|
| Q-001 |  |  |  |

### Najważniejsze ustalenia

- 

### Sceny-kotwice i wypłaty

- 

### Sprzeczności i jawne luki

- 

### Kolejka K4

- 

### Kontrola K1

- Zakres: 100% kart pozostających w kanonicznej bazie; ledger, raporty i podgląd kompilacji zostają w `_work/K1/k1-lite-v2/`
- Kontrolę wykonuje w całości walidator: hash per źródło, zakres linii, timestamp oraz obecność dosłownej `TREŚCI` we wskazanym miejscu
- `SOURCE_FIDELITY_CHECK: PASS` jest dozwolony wyłącznie wtedy, gdy zero kart pozostaje niepotwierdzonych maszynowo
- Przed `PASS` Dawid czyta deterministyczny `editorial-review.md`; aktualny receipt `K1_LITE_V2_EDITORIAL_REVIEW_RECEIPT_V1` wiąże SHA snapshotu i artefaktu z `actor: DAWID`. Tylko Dawid potwierdza konflikty. Jego decyzje pozostają w ledgerze, a kompilator potwierdza sześć bramek, w tym `editorial_review_ready`, pokrycie K0 i konkretny `STOP_REASON`. Klasa źródła bez rozpoznanej proweniencji ma zachowawcze `D`, nie domyślne `B`
- Wynik walidatora (AutoCheckedCards / ManualCheckCards):

## 2. Rejestr logicznych źródeł

Hash liczy się per źródło (kolumna SHA-256). Rejestr tworzy `Compile-K1LiteV2.ps1`; `tools/Build-SourceManifest.ps1` służy tylko do technicznego spisu.
REZERWA wymaga tylko: ID, pliku/URL i krótkiej uwagi; SHA-256 jest zalecane, ale staje się obowiązkowe dopiero po awansie do CELOWE albo RDZEŃ. Aktywne PDF/MD/TXT/SRT/VTT muszą leżeć bezpośrednio w `sources/`; obsługiwanego pliku zagnieżdżonego nie wolno rozliczyć wzorcem `katalog/**`. Nieobsługiwane pliki techniczne oraz zaplecze w `sources/_oryginaly/` są poza automatycznym rejestrem. Rola TECHNICZNE pozostaje wyłącznie dla pojedynczego, jawnie wskazanego pliku w zatwierdzonym fallbacku.

| ID | Plik/URL i zaplecze | Autor/instytucja | Data | Klasa A–D | Rola: RDZEŃ/CELOWE/REZERWA/WYŁĄCZONE/TECHNICZNE | Zakres sprawdzony | SHA-256 źródła | Karty/wynik | Uwagi |
|---|---|---|---|---|---|---|---|---|---|
| #S-001 |  |  |  |  |  |  |  |  |  |

## 3. Karty dowodowe

Karta ma cztery pola i nic więcej. `TREŚĆ` jest **dosłownym fragmentem ze źródła** —
to ona pełni rolę cytatu do kontroli maszynowej. Autor, data, tytuł i klasa źródła
żyją w rejestrze `#S` i nie są kopiowane do kart.

### #P-001

TREŚĆ:
ŹRÓDŁO_ID: #S-001
LOKALIZACJA: P0120/L3-L8 (PDF), L120-L125 (MD/TXT) albo [00:02:10.000-00:02:16.500] (SRT/VTT)
QA_K1: DO_SPRAWDZENIA

## 4. Changelog

- K1:
