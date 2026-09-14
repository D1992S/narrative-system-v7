# Kontrakt Narrative V2

NARRATIVE_V2_CONTRACT: 2026-08-31_NARRATIVE_V2
NARRATIVE_V2_STATUS: PILOT_ONLY

Ten dokument jest nadrzędnym kontraktem narracyjnym dla projektów, których `meta.md` zawiera `WORKFLOW_REVISION: 2026-08-31_NARRATIVE_V2`. Nie zmienia projektów `2026-08-30_K1_LITE_V2`; one pozostają obsługiwanym torem legacy.

## Własność decyzji

- Dawid: W0, wybór kierunku, zatwierdzenie dokładnego `AUTHOR_TEXT`, profilu głosu, polityki czasu, K5, testu A/B i ewentualnej aktywacji produkcyjnej.
- ChatGPT/Codex: K0, K1, K2, K2B, kompilacja deterministyczna, trzy niezależne kontrole K4 i walidacja techniczna.
- Claude: wyłącznie autor prozy K3 w świeżym kontekście dla jednego aktu.
- Żaden automat nie może sam wystawić decyzji lub akceptacji przypisanej Dawidowi.

## Trasa V2

`W0 → K0 → K1 → K2 → K2B → K3 → K4 → K5 → COMPLETE`

1. K1 publikuje jedną kanoniczną bazę dowodów; K2B może dodać suplement tylko przez kontrolowany merge.
2. K2 zapisuje `STORY_ENGINE_V2`: Story DNA, kontrakt hooka i finału, NQ, NR, VC, Scene Weave, akty oraz maksymalnie siedem atomowych CID na akt.
3. Profil głosu musi być fizycznie zatwierdzony przez Dawida na podstawie dokładnych fragmentów ważnych finałów K5 i jawnie przypięty do projektu przed zamrożeniem prefixu.
4. Model K3, ustawienia i stabilny prefix są zamrażane. Zmiana modelu, zasad, głosu, Story Spine albo źródeł powoduje jawne `STALE` i regenerację zależnych artefaktów.
5. Każdy akt powstaje w świeżym kontekście. Akt prosty przechodzi constraint preflight; akt złożony dodatkowo przechodzi beat sheet i beat preflight.
6. Następny akt nie rusza bez niezależnego `CONTINUITY_ATTEST` poprzedniego aktu. Otwarcia i zamknięcia są przenoszone jako typy ruchów, nie jako pełna poprzednia proza.
7. Draft jest składany deterministycznie z zaakceptowanych bloków i mapy śladów. Czysta narracja nie zawiera nagłówków technicznych ani znaczników produkcyjnych.
8. K4 uruchamia osobno EDITOR, VERIFY i COLD_READER. Każdy run ma oddzielny kontekst, task ID, wejścia, wyjście i receipt. Kompilator buduje raporty dopiero z trzech ważnych dowodów.
9. Każda korekta po K4 przechodzi przez jawny impact review albo pełne ponowienie zależnych kontroli. Carry-forward jest dozwolony tylko dla niezmienionych, hash-bound wejść.
10. K5 jest byte-identical względem zatwierdzonego draftu. Każda zmiana narracji, nawet mała, otwiera K3; system nie pozwala poprawiać tekstu poza śladem.

## Reguły jakości i kosztu

- V2 nie używa targetów słów, znaków ani rozmiaru rozdziału. `TARGET_MINUTES` to GUIDE albo zatwierdzony `HARD_MAX`, kontrolowany dopiero po kompletności narracyjnej.
- Nie ma norm liczbowych humoru, cliffhangerów ani kontaktów z widzem. Każdy VC musi mieć funkcję, węzeł i ryzyko; `AUTHOR_TEXT` wymaga exact-text receiptu.
- Źródła i granice wiedzy wygrywają z dramaturgią. K3 widzi tylko wybrane karty i lokalizacje potrzebne dla aktu; K4 VERIFY ponownie czyta źródła.
- Cache i telemetria są optymalizacją zgodną z `RUN-TELEMETRY-SCHEMA.md`. Ich awaria nie może zmienić wyniku ani uszkodzić artefaktu.
- `PILOT_ONLY` pozostaje obowiązkowe do czasu jawnego testu A/B na trzech benchmarkach, wyniku co najmniej 2/3 oraz decyzji Dawida.

## Fail-closed

Pracę zatrzymują między innymi: mieszane schematy, brak ważnego originu, niezatwierdzony profil głosu, brak receiptu wyboru profilu, ponad siedem atomowych CID, ukryta lista obowiązków, fałszywy modelowy PASS, stale prefix/model/source, brak kolejności aktów, nieważny continuity chain, skażenie ról K4, stary receipt K4/K5 oraz zmiana finału po akceptacji.

## Dokumenty wykonawcze

- Schemat architektury: `TEMPLATES/PROJECT/02-architektura-odcinka.md`
- Atomowość: `_SYSTEM/NARRATIVE/CONSTRAINT-ATOMICITY-SCHEMA.md`
- K3: `_SYSTEM/NARRATIVE/K3-RULES-CORE.md`, `BEAT-PREFLIGHT-SCHEMA.md`, `CONTINUITY-SCHEMA.md`
- Głos: `_SYSTEM/NARRATIVE/VOICE-PROFILE-SCHEMA.md`
- K4: pliki `EDITOR-*`, `VERIFY-*`, `COLD-READER-*`, `QA-IMPACT-SCHEMA.md`
- Integralność instrukcji: `NARRATIVE-INSTRUCTION-MANIFEST.json`; telemetria: `RUN-TELEMETRY-SCHEMA.md`; protokół pilota: `AB-TEST-PROTOCOL.md` i `AB-TEST-STATUS.json`
- Komendy: `_SYSTEM/04-START-I-KOMENDY.md` i `tools/README.md`
