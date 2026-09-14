# Pipeline System-v7.0

NARRATIVE_V2_CONTRACT: 2026-08-31_NARRATIVE_V2
NARRATIVE_V2_STATUS: PILOT_ONLY

Najpierw odczytaj `WORKFLOW_REVISION` projektu.

## Jedna wersja dla nowych projektów

Od 2026-09-12, na polecenie Dawida, jedyną wersją wybieraną dla nowych projektów jest `2026-08-31_NARRATIVE_V2`. `New-Project.ps1` wybiera ją domyślnie. Status jakości pozostaje `PILOT_ONLY`: uporządkowanie i wybór wersji nie są wynikiem testu A/B ani zatwierdzeniem profilu głosu. Istniejące projekty zachowują swój origin, rewizję, tekst i receipty; nie są automatycznie migrowane. Kod zgodności służy zachowaniu dostępu do tych projektów, nie stanowi drugiej instalacji systemu.

Szablony `tools/compatibility/PROJECT-LEGACY-K1-LITE-V2` są techniczną zależnością starszych projektów i testów. Nie wolno mieszać ich artefaktów z Narrative V2.

## Tor Narrative V2

Projekt powstaje przez `New-Project.ps1`; Narrative V2 jest domyślne. Starszy jawny przełącznik `-NarrativeV2Pilot` nadal działa.

| Etap | Właściciel | Wejście | Wynik / bramka |
|---|---|---|---|
| W0 | Dawid | pomysł i fizyczne źródła | decyzja GO / GO WARUNKOWE / NO-GO |
| K0 | ChatGPT | W0 | `00-fundament-projektu.md`, K0 PASS |
| K1 | ChatGPT | źródła | opublikowane `01-baza-dowodow.md`, ledger i receipt |
| K2 | ChatGPT | fundament + K1 | `STORY_ENGINE_V2`, architektura PASS |
| K2B | ChatGPT | luki K2 | BRAK albo suplement K1 i ponowna architektura |
| K3 | Claude | zamrożone pakiety aktów | attested akty i złożony `03-draft.md` |
| K4 | ChatGPT | czysty draft i kontrolowane wejścia | trzy proofy, proof set, `04` i `04B` |
| K5 | Dawid | draft + raporty K4 | byte-identical `05-FINAL-SCRIPT.md` i receipt |
| COMPLETE | system | ważny K5 | zamknięty projekt |

## Szczegóły V2

### W0–K1

- Źródła trafiają do `sources/`; `_oryginaly/` jest tylko zapleczem technicznym.
- K1 Lite V2 pracuje w izolacji. Publikacja jest deterministyczna i nie może bezpośrednio zmienić 01 bez pełnego pokrycia, decyzji i postwalidacji.
- Manual fallback wymaga osobnego receiptu Dawida.

### K2–K2B

- K2 tworzy dwie realne osie kierunku, jedną decyzję, Story DNA, hook/final contract, NQ, NR, VC, Scene Weave i akty.
- Każdy akt ma najwyżej siedem machine-valid atomowych CID. Ukryta lista obowiązków lub modelowy fałszywy PASS zatrzymuje etap.
- K2B nie jest automatycznym researchem. Najpierw decyzja BRAK / SUPLEMENT / POWRÓT K2. Suplement łączy wyłącznie `Merge-K1LiteV2Supplement.ps1`.

### Przygotowanie K3

1. Dawid zatwierdza exact exemplars przez `Approve-VoiceProfile.ps1`.
2. Dawid wybiera profil dla projektu przez `Set-VoiceProfileForProject.ps1`.
3. Model i ustawienia są zapisywane przez `Set-K3ModelManifest.ps1`.
4. `Build-K3PacketsV2.ps1 -Write` tworzy stabilny prefix, manifest i pakiety aktów.

### Każdy akt K3

1. `Start-K3ConstraintPreflight.ps1` → niezależny run ChatGPT/Codex → `New-NarrativeRunReceipt.ps1`.
2. Dla COMPLEX: `Start-K3Act.ps1` w trybie planu → `Import-K3BeatSheet.ps1` → `Start-K3BeatPreflight.ps1` → receipt.
3. Claude otrzymuje jeden packet w świeżym kontekście. Wynik importuje `Import-K3Act.ps1`.
4. `Start-ContinuityAttest.ps1` tworzy ślepy run; po receipcie `Accept-ContinuityAttest.ps1` zamyka akt.
5. Kolejny akt startuje dopiero po kroku 4. Po ostatnim `Assemble-K3Draft.ps1` składa draft.

### K4

1. `Start-K4Lenses.ps1` zamraża rozdzielone wejścia dla EDITOR, VERIFY i COLD_READER.
2. Każdy run wykonuje się w oddzielnym kontekście i kończy przez `New-NarrativeRunReceipt.ps1`.
3. `Compile-K4ProofSet.ps1` sprawdza niezależność, pełne pokrycie i continuity chain, a następnie tworzy proof set i raporty.
4. Korekta wymaga `Compare-DraftV2.ps1`, impact review i odpowiedniej reruny. Carry-forward tworzy wyłącznie `New-QACarryForwardReceipt.ps1`.

### K5

- `Approve-K5FinalV2.ps1` wymaga jawnego `-DawidApproved`, konkretnej notatki, kompletnego K4 i byte-identical finalu.
- Nie ma „drobnej poprawki” poza śladem. Każda zmiana narracji używa `Reopen-Stage.ps1 -TargetStage K3 -ReasonCode SIGNIFICANT_K5_CORRECTION`.

## Stan blokady i awarii

- Brak źródeł, sprzeczność, przeciążony packet, stale prefix/model, niepełna ciągłość lub nieważny proof powodują FAIL albo kontrolowany `PACKET_INSUFFICIENT`.
- Awaria cache lub telemetrii nie zmienia wyniku merytorycznego; narzędzie ma przerwać albo pracować bez optymalizacji, nigdy zapisać półproduktu.
